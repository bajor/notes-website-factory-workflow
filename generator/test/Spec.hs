{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Codec.Picture (Image, PixelRGB8 (PixelRGB8), PixelRGBA8 (PixelRGBA8), generateImage, pixelAt)
import Data.Aeson (Value (Object, String), toJSON)
import Factory.Domain
import Factory.Evaluation (CaptureTile (CaptureTile), EvaluationResult (evaluationPassed), bodyIsReady, calculateDifference, captureTiles, stitchTiles)
import Factory.Geometry (boardMatrix, identityMatrix, multiplyMatrix)
import Factory.Interpreter (ColorSpaceResource (SupportedColorSpace, UnsupportedColorSpace), Resources (Resources), VisualResource (RasterResource, VectorResource), interpretOperators)
import Factory.Pipeline (outputCompanionPaths, validateOutputPath)
import Factory.Pdf (classifyUrl, rejectDecode, rgbaImage)
import Factory.Site (renderIndexTemplate, validateScene)
import Factory.Vectorize (ImageDisposition (..), classifyImage, opaqueHighlighter, traceImage)
import Pdf.Content (Op (..), Operator)
import Pdf.Core (Object (Array, Name, Number))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import qualified Data.ByteString as ByteString
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import qualified Data.Scientific as Scientific
import qualified Data.Text as Text
import qualified Data.Vector as Vector

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "freeform factory"
    [ geometryTests
    , interpreterTests
    , imageTests
    , vectorizationTests
    , linkTests
    , validationTests
    , siteTests
    , evaluationTests
    , pipelineTests
    ]

geometryTests :: TestTree
geometryTests =
  testGroup
    "geometry"
    [ testCase "identity matrix leaves another matrix unchanged" $ do
        let matrix = Matrix 2 0 0 3 10 20
        multiplyMatrix identityMatrix matrix @?= matrix
    , testCase "board matrix flips the PDF vertical axis" $
        boardMatrix (Coordinate 100) (Matrix 1 0 0 1 10 20)
          @?= Matrix 1 0 0 (-1) 10 80
    ]

interpreterTests :: TestTree
interpreterTests =
  testGroup
    "operator interpreter"
    [ testCase "image operators emit a board-space image node" $
        interpretOperators pageHeight imageResources [operator Op_cm [2, 0, 0, 3, 10, 20], (Op_Do, [Name "Im1"])]
          @?= Right [ImageNode (AssetId "asset-1") (Matrix 2 0 0 (-3) 10 80) 1 []]
    , testCase "mixed image operators preserve source order" $
        interpretOperators pageHeight mixedResources [(Op_Do, [Name "Raster"]), (Op_Do, [Name "Vector"])]
          @?= Right
            [ ImageNode (AssetId "asset-1") (Matrix 1 0 0 (-1) 0 100) 1 []
            , VectorArtworkNode [testVectorShape] (Matrix 1 0 0 (-1) 0 100) 1 []
            ]
    , testCase "a closed subpath remains the current point" $
        case interpretOperators pageHeight emptyResources closedCurveOperators of
          Right [PathNode commands _ _] -> commandAt 3 commands @?= Just (CurveTo (Point 10 90) (Point 30 80) (Point 40 60))
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "miter-limit operators reach painted path styles" $
        case interpretOperators pageHeight emptyResources [operator Op_M [4], operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])] of
          Right [PathNode _ style _] -> paintMiterLimit style @?= 4
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "miter limits below one fail explicitly" $
        interpretOperators pageHeight emptyResources [operator Op_M [0]]
          @?= Left (PdfStructureError "miter limit must be at least 1")
    , testCase "dash operators reach painted path styles" $
        case interpretOperators pageHeight emptyResources [dashOperator [28, 28] 0, operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])] of
          Right [PathNode _ style _] -> (paintDashArray style, paintDashPhase style) @?= ([28, 28], 0)
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "similarity transforms scale stroke metrics" $
        case interpretOperators pageHeight emptyResources [operator Op_cm [2, 0, 0, 2, 0, 0], operator Op_w [3], dashOperator [2, 1] 4, operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])] of
          Right [PathNode _ style _] -> (paintLineWidth style, paintDashArray style, paintDashPhase style) @?= (6, [4, 2], 8)
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "non-similarity transforms reject stroked paths" $
        interpretOperators pageHeight emptyResources [operator Op_cm [2, 0, 0, 3, 0, 0], operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])]
          @?= Left (UnsupportedOperator "stroked paths require a non-singular similarity transform")
    , testCase "small singular transforms reject stroked paths" $
        interpretOperators pageHeight emptyResources [operator Op_cm [0.000001, 0, 0, 0, 0, 0], operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])]
          @?= Left (UnsupportedOperator "stroked paths require a non-singular similarity transform")
    , testCase "all-zero dash arrays fail explicitly" $
        interpretOperators pageHeight emptyResources [dashOperator [0, 0] 0]
          @?= Left (PdfStructureError "dash array must not contain only zeros")
    , testCase "named RGB stroke colors reach painted paths" $
        case interpretOperators pageHeight namedRgbResources [(Op_CS, [Name "Cs1"]), operator Op_SC [0.75, 0.5, 0.25], operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])] of
          Right [PathNode _ style _] -> paintStroke style @?= Just (Color 0.75 0.5 0.25)
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "named RGB fill colors reach painted paths" $
        case interpretOperators pageHeight namedRgbResources [(Op_cs, [Name "Cs1"]), operator Op_sc [0.75, 0.5, 0.25], operator Op_re [0, 0, 10, 10], (Op_f, [])] of
          Right [PathNode _ style _] -> fmap fst (paintFill style) @?= Just (Color 0.75 0.5 0.25)
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "selecting a color space resets its current color" $
        case interpretOperators pageHeight namedRgbResources [operator Op_RG [1, 0, 0], (Op_CS, [Name "Cs1"]), operator Op_m [0, 0], operator Op_l [10, 10], (Op_S, [])] of
          Right [PathNode _ style _] -> paintStroke style @?= Just (Color 0 0 0)
          result -> assertFailure ("unexpected interpreter result: " <> show result)
    , testCase "selecting an unsupported named color space fails explicitly" $
        interpretOperators pageHeight unsupportedColorResources [(Op_CS, [Name "PatternSpace"])]
          @?= Left (UnsupportedOperator "unsupported named color space: PatternSpace")
    , testCase "out-of-range CMYK components fail before conversion" $
        interpretOperators pageHeight emptyResources [operator Op_K [2, 0, 0, 0]]
          @?= Left (PdfStructureError "CMYK components must be between 0 and 1")
    , testCase "PDF text fails until font decoding is supported" $
        interpretOperators pageHeight emptyResources [(Op_BT, [])]
          @?= Left (UnsupportedOperator "PDF text requires font decoding and metrics")
    ]

imageTests :: TestTree
imageTests =
  testGroup
    "image decoding"
    [ testCase "declared RGB samples require three bytes per pixel" $
        case rgbaImage 1 1 3 "\NUL" Nothing of
          Left buildError -> buildError @?= UnsupportedImage "decoded image samples have the wrong length"
          Right _ -> assertFailure "RGB image unexpectedly accepted one sample byte"
    , testCase "decoded soft-mask alpha is preserved per pixel" $
        case rgbaImage 2 1 3 (ByteString.pack [10, 20, 30, 40, 50, 60]) (Just (ByteString.pack [1, 95])) of
          Right image -> case (pixelAt image 0 0, pixelAt image 1 0) of
            (PixelRGBA8 _ _ _ firstAlpha, PixelRGBA8 _ _ _ secondAlpha) -> [firstAlpha, secondAlpha] @?= [1, 95]
          Left buildError -> assertFailure ("unexpected image decoding error: " <> show buildError)
    , testCase "image Decode arrays fail explicitly" $
        rejectDecode (Just (Name "DecodeArray"))
          @?= Left (UnsupportedImage "image Decode arrays are not supported")
    ]

vectorizationTests :: TestTree
vectorizationTests =
  testGroup
    "vectorization"
    [ testCase "opaque images remain raster" $
        classifyImage Nothing @?= Right PreserveRaster
    , testCase "empty soft masks fail explicitly" $
        classifyImage (Just ByteString.empty) @?= Left (UnsupportedImage "soft mask is empty")
    , testCase "fully transparent soft masks fail explicitly" $
        classifyImage (Just (ByteString.pack [0, 0])) @?= Left (UnsupportedImage "soft mask contains no visible artwork")
    , testCase "nonzero masks below the tracing cutoff remain raster" $
        classifyImage (Just (ByteString.pack [0, 1, 95])) @?= Right PreserveLowAlphaRaster
    , testCase "alpha at the tracing cutoff remains traceable" $
        classifyImage (Just (ByteString.pack [96])) @?= Right TraceAsVector
    , testCase "rounded screenshots with nearly opaque masks remain raster" $
        classifyImage (Just (ByteString.pack (0 : replicate 999 255))) @?= Right PreserveRaster
    , testCase "linked cards with less than one percent transparency remain raster" $
        classifyImage (Just (ByteString.pack (replicate 8 0 <> replicate 992 255))) @?= Right PreserveRaster
    , testCase "one percent transparency remains raster" $
        classifyImage (Just (ByteString.pack (replicate 10 0 <> replicate 990 255))) @?= Right PreserveRaster
    , testCase "ambiguous soft masks fail classification" $
        classifyImage (Just (ByteString.pack (replicate 15 0 <> replicate 985 255)))
          @?= Left (UnsupportedImage "soft-masked image is too opaque to classify safely")
    , testCase "two percent transparency becomes vector artwork" $
        classifyImage (Just (ByteString.pack (replicate 20 0 <> replicate 980 255))) @?= Right TraceAsVector
    , testCase "a filled rectangle produces one closed vector path" $
        case traceImage solidVectorImage of
          Right [shape] ->
            let path = unVectorPath (vectorPath shape)
             in assertBool "trace has one closed contour" (Text.count "M" path == 1 && Text.isSuffixOf "Z" path)
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "transparent holes remain separate closed contours" $
        case traceImage vectorImageWithHole of
          Right [shape] -> Text.count "M" (unVectorPath (vectorPath shape)) @?= 2
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "diagonal staircases contain fractional contour coordinates" $
        case traceImage diagonalStaircaseImage of
          Right [shape] -> assertBool "trace is not constrained to source-pixel corners" (Text.isInfixOf "0.854248" (unVectorPath (vectorPath shape)))
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "alpha ramps interpolate contour crossings" $
        case traceImage alphaRampImage of
          Right [shape] -> assertBool "trace contains the interpolated crossing" (Text.isInfixOf "0.623047" (unVectorPath (vectorPath shape)))
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "cutoff-alpha pixels retain a closed trace" $
        case traceImage cutoffAlphaImage of
          Right [shape] ->
            let path = unVectorPath (vectorPath shape)
             in assertBool "trace is nonempty and closed" (not (Text.null path) && Text.isSuffixOf "Z" path)
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "mixed-opacity artwork retains a faint vector layer" $
        case traceImage mixedOpacityImage of
          Right [faintShape, opaqueShape] ->
            map vectorOpacity [faintShape, opaqueShape] @?= [64 / 255, 1]
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "faint strokes interpolate their outer boundary" $
        case traceImage faintStrokeImage of
          Right (shape : _) -> assertBool "faint crossing is fractional" (Text.isInfixOf "0.189716" (unVectorPath (vectorPath shape)))
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "isolated cutoff components survive beside opaque artwork" $
        case traceImage (cutoffComponentsImage 1) of
          Right [shape] -> Text.count "M" (unVectorPath (vectorPath shape)) @?= 2
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "cutoff pairs do not degrade separate opaque contours" $
        case (traceImage (cutoffComponentsImage 0), traceImage (cutoffComponentsImage 2)) of
          (Right [opaqueShape], Right [mixedShape]) ->
            assertBool "opaque contour is unchanged" (unVectorPath (vectorPath opaqueShape) `Text.isSuffixOf` unVectorPath (vectorPath mixedShape))
          result -> assertFailure ("unexpected trace results: " <> show result)
    , testCase "simplification retains a thin cutoff stroke's area" $
        case traceImage (generateImage (\_ _ -> PixelRGBA8 0 0 0 96) 3 1) of
          Right [shape] -> assertBool "stroke was not collapsed to a line" (Text.count "L" (unVectorPath (vectorPath shape)) >= 3)
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "sub-threshold edge samples contribute to interpolation" $
        case traceImage subThresholdRampImage of
          Right [shape] -> assertBool "crossing uses source edge alpha" (Text.isInfixOf "0.411458" (unVectorPath (vectorPath shape)))
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "adjacent opacity layers share a boundary" $
        case traceImage mixedOpacityImage of
          Right [faintShape, opaqueShape] ->
            assertBool "both opacity layers use the source boundary" (Text.isInfixOf "0.272455" (unVectorPath (vectorPath faintShape)) && Text.isInfixOf "0.272455" (unVectorPath (vectorPath opaqueShape)))
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "adjacent styles share an interpolated boundary" $
        case traceImage adjacentStylesImage of
          Right [leftShape, rightShape] ->
            assertBool ("both styles use the source boundary: " <> show [vectorPath leftShape, vectorPath rightShape]) (Text.isInfixOf "0.5" (unVectorPath (vectorPath leftShape)) && Text.isInfixOf "0.5" (unVectorPath (vectorPath rightShape)))
          result -> assertFailure ("unexpected trace result: " <> show result)
    , testCase "contour tracing is deterministic" $
        traceImage diagonalStaircaseImage @?= traceImage diagonalStaircaseImage
    , testCase "nonzero highlighter pixels become opaque without changing RGB" $
        case opaqueHighlighter translucentHighlighter of
          Just image -> pixelAt image 0 0 @?= PixelRGBA8 255 192 0 255
          Nothing -> assertFailure "highlighter stroke was not recognized"
    , testCase "transparent highlighter pixels retain their source RGB and alpha" $
        case opaqueHighlighter highlighterWithTransparentPixels of
          Just image -> pixelAt image 0 0 @?= PixelRGBA8 12 34 56 0
          Nothing -> assertFailure "highlighter stroke was not recognized"
    , testCase "a compact translucent color block keeps its source opacity" $
        case opaqueHighlighter translucentColorBlock of
          Nothing -> pure ()
          Just _ -> assertFailure "compact color block was classified as a highlighter stroke"
    ]

linkTests :: TestTree
linkTests =
  testGroup
    "link classification"
    [ testCase "Algo Arcade game routes receive a game target" $
        classifyUrl gameUrl @?= Right (Game (GameUrl gameUrl))
    , testCase "Algo Arcade host matching is case insensitive" $
        classifyUrl "https://BAJOR.GITHUB.IO/algo-arcade/#/games/example-game"
          @?= Right (Game (GameUrl "https://BAJOR.GITHUB.IO/algo-arcade/#/games/example-game"))
    , testCase "HTTP game routes remain external links" $
        classifyUrl "http://bajor.github.io/algo-arcade/#/games/example-game"
          @?= Right (External (WebUrl "http://bajor.github.io/algo-arcade/#/games/example-game"))
    , testCase "game routes with credentials remain external links" $
        classifyUrl "https://user@bajor.github.io/algo-arcade/#/games/example-game"
          @?= Right (External (WebUrl "https://user@bajor.github.io/algo-arcade/#/games/example-game"))
    , testCase "game routes with explicit ports remain external links" $
        classifyUrl "https://bajor.github.io:443/algo-arcade/#/games/example-game"
          @?= Right (External (WebUrl "https://bajor.github.io:443/algo-arcade/#/games/example-game"))
    , testCase "other paths remain external links" $
        classifyUrl "https://bajor.github.io/other/#/games/example-game"
          @?= Right (External (WebUrl "https://bajor.github.io/other/#/games/example-game"))
    , testCase "non-game pages remain external links" $
        classifyUrl "https://bajor.github.io/algo-arcade/" @?= Right (External (WebUrl "https://bajor.github.io/algo-arcade/"))
    , testCase "lookalike game hosts remain external links" $
        classifyUrl "https://bajor.github.io.evil.example/algo-arcade/#/games/example"
          @?= Right (External (WebUrl "https://bajor.github.io.evil.example/algo-arcade/#/games/example"))
    , testCase "game targets serialize with their distinct kind" $
        case toJSON (LinkNode (Game (GameUrl gameUrl)) (Rect 1 2 3 4)) of
          Object node -> case KeyMap.lookup "target" node of
            Just (Object target) -> KeyMap.lookup "kind" target @?= Just (String "game")
            value -> assertFailure ("unexpected target JSON: " <> show value)
          value -> assertFailure ("unexpected link JSON: " <> show value)
    ]

validationTests :: TestTree
validationTests =
  testGroup
    "scene validation"
    [ testCase "an image must reference a declared asset" $
        validateScene (sceneWith [] [ImageNode (AssetId "missing") identityMatrix 1 []])
          @?= Left (InvalidScene "image node references a missing asset")
    , testCase "a clip cannot hide a full-board raster image" $
        validateScene (sceneWith [testAsset] [ImageNode (assetId testAsset) (Matrix 100 0 0 100 0 0) 1 [fullPageClip]])
          @?= Left (InvalidScene "a full-board raster image is not allowed")
    , testCase "unreferenced raster assets are rejected" $
        validateScene (sceneWith [testAsset] [])
          @?= Left (InvalidScene "scene contains an unreferenced asset")
    , testCase "vector-only scenes are valid" $
        case validateScene (sceneWith [] [VectorArtworkNode [testVectorShape] identityMatrix 1 []]) of
          Right _ -> pure ()
          Left buildError -> assertFailure ("unexpected validation error: " <> show buildError)
    , testCase "rotated vector artwork is valid" $
        case validateScene (sceneWith [] [VectorArtworkNode [testVectorShape] (Matrix 0 1 (-1) 0 10 10) 1 []]) of
          Right _ -> pure ()
          Left buildError -> assertFailure ("unexpected validation error: " <> show buildError)
    , testCase "an affine image bounding box does not imply full-board coverage" $
        case validateScene (sceneWith [testAsset] [ImageNode (assetId testAsset) (Matrix 100 100 100 0 0 0) 1 []]) of
          Right _ -> pure ()
          Left buildError -> assertFailure ("unexpected validation error: " <> show buildError)
    , testCase "overflowing finite determinants retain full-board detection" $
        validateScene (sceneWith [testAsset] [ImageNode (assetId testAsset) (Matrix 2e306 0 0 2e306 0 0) 1 []])
          @?= Left (InvalidScene "a full-board raster image is not allowed")
    , testCase "mixed-scale image axes retain full-board detection" $
        validateScene (Scene (Coordinate 1e306) (Coordinate 1e-100) [testAsset] [ImageNode (assetId testAsset) (Matrix 1e306 0 0 1e-100 0 0) 1 []])
          @?= Left (InvalidScene "a full-board raster image is not allowed")
    ]

evaluationTests :: TestTree
evaluationTests =
  testGroup
    "visual evaluation"
    [ testCase "a blank rendering fails against sparse reference ink" $
        evaluationPassed (calculateDifference sparseReference blankImage) @?= False
    , testCase "in-bound output uses one capture tile" $
        captureTiles 6051 3020 @?= [CaptureTile 0 0 6051 3020]
    , testCase "oversized output uses bounded row-major tiles" $
        captureTiles 24204 12080
          @?= [ CaptureTile 0 0 8192 4096
              , CaptureTile 8192 0 8192 4096
              , CaptureTile 16384 0 7820 4096
              , CaptureTile 0 4096 8192 4096
              , CaptureTile 8192 4096 8192 4096
              , CaptureTile 16384 4096 7820 4096
              , CaptureTile 0 8192 8192 3888
              , CaptureTile 8192 8192 8192 3888
              , CaptureTile 16384 8192 7820 3888
              ]
    , testCase "stitching preserves the tile boundary pixels" $
        case stitchTiles 8193 1 [(CaptureTile 0 0 8192 1, redTile), (CaptureTile 8192 0 1 1, blueTile)] of
          Left message -> assertFailure (Text.unpack message)
          Right image -> (pixelAt image 8191 0, pixelAt image 8192 0) @?= (PixelRGB8 255 0 0, PixelRGB8 0 0 255)
    , testCase "stitching preserves the row boundary pixels" $
        case stitchTiles 1 4097 [(CaptureTile 0 0 1 4096, redColumn), (CaptureTile 0 4096 1 1, blueTile)] of
          Left message -> assertFailure (Text.unpack message)
          Right image -> (pixelAt image 0 4095, pixelAt image 0 4096) @?= (PixelRGB8 255 0 0, PixelRGB8 0 0 255)
    , testCase "readiness comes from the body attribute" $
        bodyIsReady "<title>data-ready=\"true\"</title><body data-failed=\"true\">" @?= False
    , testCase "a ready body passes the browser gate" $
        bodyIsReady "<body data-ready=\"true\"></body>" @?= True
    ]
  where
    redTile = generateImage (\_ _ -> PixelRGB8 255 0 0) 8192 1
    redColumn = generateImage (\_ _ -> PixelRGB8 255 0 0) 1 4096
    blueTile = generateImage (\_ _ -> PixelRGB8 0 0 255) 1 1

siteTests :: TestTree
siteTests =
  testGroup
    "site metadata"
    [ testCase "blank site titles are rejected" $
        mkSiteTitle "  \n"
          @?= Left (InvalidSiteTitle "site title must not be empty")
    , testCase "control characters in site titles are rejected" $
        mkSiteTitle "Notes\tSite"
          @?= Left (InvalidSiteTitle "site title must not contain control characters")
    , testCase "site titles are escaped in generated HTML" $
        case mkSiteTitle "<Notes & \"Ideas\">" of
          Left buildError -> assertFailure ("unexpected title error: " <> show buildError)
          Right title ->
            renderIndexTemplate title "{{SITE_TITLE}}|{{SITE_ARIA_LABEL}}"
              @?= "&lt;Notes &amp; &quot;Ideas&quot;&gt;|Zoomable page: &lt;Notes &amp; &quot;Ideas&quot;&gt;"
    , testCase "site titles do not expand template markers" $
        case mkSiteTitle "{{SITE_ARIA_LABEL}}" of
          Left buildError -> assertFailure ("unexpected title error: " <> show buildError)
          Right title ->
            renderIndexTemplate title "{{SITE_TITLE}}|{{SITE_ARIA_LABEL}}"
              @?= "{{SITE_ARIA_LABEL}}|Zoomable page: {{SITE_ARIA_LABEL}}"
    ]

pipelineTests :: TestTree
pipelineTests =
  testGroup
    "pipeline paths"
    [ testCase "an output directory containing the repository is rejected" $
        validateOutputPath "/workspace/repository" "/workspace"
          @?= Left (IoError "a removable path must not overlap a protected root")
    , testCase "an output directory inside the repository is rejected" $
        validateOutputPath "/workspace/repository" "/workspace/repository/dist"
          @?= Left (IoError "a removable path must not overlap a protected root")
    , testCase "a sibling output directory is accepted" $
        validateOutputPath "/workspace/repository" "/workspace/dist"
          @?= Right ()
    , testCase "trailing separators do not put staging inside the output" $
        outputCompanionPaths "/workspace/repository/dist/"
          @?= ("/workspace/repository/dist", "/workspace/repository/dist.building", "/workspace/repository/dist.previous")
    ]

pageHeight :: Coordinate PdfSpace
pageHeight = Coordinate 100

gameUrl :: Text.Text
gameUrl = "https://bajor.github.io/algo-arcade/#/games/example-game"

emptyResources :: Resources
emptyResources = Resources Map.empty Map.empty Map.empty

imageResources :: Resources
imageResources = Resources (Map.singleton "Im1" (RasterResource (AssetId "asset-1"))) Map.empty Map.empty

mixedResources :: Resources
mixedResources =
  Resources
    ( Map.fromList
        [ ("Raster", RasterResource (AssetId "asset-1"))
        , ("Vector", VectorResource [testVectorShape])
        ]
    )
    Map.empty
    Map.empty

namedRgbResources :: Resources
namedRgbResources = Resources Map.empty Map.empty (Map.singleton "Cs1" (SupportedColorSpace RgbColorSpace))

unsupportedColorResources :: Resources
unsupportedColorResources = Resources Map.empty Map.empty (Map.singleton "PatternSpace" UnsupportedColorSpace)

testVectorShape :: VectorShape
testVectorShape = VectorShape (VectorPath "M0,0L1,0L1,1Z") (Color 0 0 0) 1

operator :: Op -> [Double] -> Operator
operator name values = (name, map (Number . Scientific.fromFloatDigits) values)

dashOperator :: [Double] -> Double -> Operator
dashOperator values phase =
  ( Op_d
  , [ Array (Vector.fromList (map (Number . Scientific.fromFloatDigits) values))
    , Number (Scientific.fromFloatDigits phase)
    ]
  )

closedCurveOperators :: [Operator]
closedCurveOperators =
  [ operator Op_m [10, 10]
  , operator Op_l [20, 10]
  , (Op_h, [])
  , operator Op_v [30, 20, 40, 40]
  , (Op_S, [])
  ]

commandAt :: Int -> [PathCommand] -> Maybe PathCommand
commandAt index commands = case drop index commands of
  command : _ -> Just command
  [] -> Nothing

sceneWith :: [Asset] -> [SceneNode] -> Scene 'Unvalidated
sceneWith assets nodes = Scene (Coordinate 100) (Coordinate 100) assets nodes

testAsset :: Asset
testAsset = Asset (AssetId "asset-1") "assets/asset-1.png" 10 10

fullPageClip :: ClipPath
fullPageClip =
  ClipPath
    ClipNonZero
    [ MoveTo (Point 0 0)
    , LineTo (Point 100 0)
    , LineTo (Point 100 100)
    , LineTo (Point 0 100)
    , ClosePath
    ]

sparseReference :: Image PixelRGB8
sparseReference = generateImage pixel 100 100
  where
    pixel 0 0 = PixelRGB8 0 0 0
    pixel _ _ = PixelRGB8 255 255 255

blankImage :: Image PixelRGB8
blankImage = generateImage (\_ _ -> PixelRGB8 255 255 255) 100 100

solidVectorImage :: Image PixelRGBA8
solidVectorImage = generateImage (\_ _ -> PixelRGBA8 0 0 0 255) 2 2

vectorImageWithHole :: Image PixelRGBA8
vectorImageWithHole = generateImage pixel 3 3
  where
    pixel 1 1 = PixelRGBA8 0 0 0 0
    pixel _ _ = PixelRGBA8 0 0 0 255

diagonalStaircaseImage :: Image PixelRGBA8
diagonalStaircaseImage = generateImage pixel 6 6
  where
    pixel x y
      | x >= y + offset y = PixelRGBA8 0 0 0 255
      | otherwise = PixelRGBA8 0 0 0 0
    offset y
      | even y = 0
      | otherwise = 1

alphaRampImage :: Image PixelRGBA8
alphaRampImage = generateImage pixel 2 2
  where
    pixel 0 _ = PixelRGBA8 0 0 0 0
    pixel _ _ = PixelRGBA8 0 0 0 128

cutoffAlphaImage :: Image PixelRGBA8
cutoffAlphaImage = generateImage (\_ _ -> PixelRGBA8 0 0 0 96) 1 1

faintStrokeImage :: Image PixelRGBA8
faintStrokeImage = generateImage pixel 3 1
  where
    pixel 0 _ = PixelRGBA8 0 0 0 94
    pixel 2 _ = PixelRGBA8 0 0 0 255
    pixel _ _ = PixelRGBA8 0 0 0 0

cutoffComponentsImage :: Int -> Image PixelRGBA8
cutoffComponentsImage count = generateImage pixel 8 4
  where
    pixel x y
      | y == 1 && x >= 1 && x <= count = PixelRGBA8 0 0 0 96
      | x >= 5 && x <= 6 && y >= 1 && y <= 2 = PixelRGBA8 0 0 0 255
      | otherwise = PixelRGBA8 0 0 0 0

subThresholdRampImage :: Image PixelRGBA8
subThresholdRampImage = generateImage pixel 2 2
  where
    pixel 0 _ = PixelRGBA8 0 0 0 80
    pixel _ _ = PixelRGBA8 0 0 0 128

mixedOpacityImage :: Image PixelRGBA8
mixedOpacityImage = generateImage pixel 2 2
  where
    pixel 0 _ = PixelRGBA8 0 0 0 88
    pixel _ _ = PixelRGBA8 0 0 0 255

adjacentStylesImage :: Image PixelRGBA8
adjacentStylesImage = generateImage pixel 2 2
  where
    pixel 0 _ = PixelRGBA8 0 0 0 255
    pixel _ _ = PixelRGBA8 255 0 0 255

translucentHighlighter :: Image PixelRGBA8
translucentHighlighter = generateImage (\_ _ -> PixelRGBA8 255 192 0 89) 12 2

highlighterWithTransparentPixels :: Image PixelRGBA8
highlighterWithTransparentPixels = generateImage pixel 12 2
  where
    pixel 0 _ = PixelRGBA8 12 34 56 0
    pixel _ _ = PixelRGBA8 255 192 0 89

translucentColorBlock :: Image PixelRGBA8
translucentColorBlock = generateImage (\_ _ -> PixelRGBA8 255 192 0 89) 4 4
