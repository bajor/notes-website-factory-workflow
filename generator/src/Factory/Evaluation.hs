{-# LANGUAGE OverloadedStrings #-}

-- | Produce evidence for the software-factory feedback loop.
--
-- The deployed page never uses a rendered PDF. During development, however,
-- an independent rendering of the source is a useful oracle: Poppler for a PDF
-- and the browser's direct rendering for an SVG. We compare that oracle with a
-- browser screenshot of our generated DOM/SVG scene and keep the difference
-- image as evidence for the next iteration.
module Factory.Evaluation
  ( CaptureTile (..)
  , EvaluationResult (..)
  , Reference (..)
  , bodyIsReady
  , calculateDifference
  , captureTiles
  , runVisualEvaluation
  , selectDetailRegions
  , stitchTiles
  ) where

import Codec.Picture
  ( DynamicImage
  , Image (..)
  , PixelRGB8 (PixelRGB8)
  , convertRGB8
  , generateImage
  , readImage
  , writePng
  )
import Control.Exception (IOException, finally, try)
import Control.Monad (forM_)
import Control.Monad.Primitive (PrimMonad, PrimState)
import Control.Monad.ST (runST)
import Data.Aeson (encode, object, (.=))
import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Data.Ord (Down (Down))
import Data.Text (Text)
import Data.Word (Word8)
import Factory.Domain (BoardSpace, BuildError (EvaluationError), Coordinate (unCoordinate))
import System.Directory (copyFile, createDirectoryIfMissing, doesPathExist, makeAbsolute, removePathForcibly)
import System.Exit (ExitCode (ExitSuccess))
import System.Environment (lookupEnv)
import System.FilePath (dropExtension, takeDirectory, takeFileName, (</>))
import System.IO (IOMode (ReadMode), withBinaryFile)
import System.Process (readProcessWithExitCode)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as LazyByteString
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import qualified Data.Vector.Storable as Vector
import qualified Data.Vector.Storable.Mutable as MutableVector

data CaptureTile = CaptureTile
  { captureX :: Int
  , captureY :: Int
  , captureWidth :: Int
  , captureHeight :: Int
  }
  deriving stock (Eq, Show)

data EvaluationResult = EvaluationResult
  { evaluationMeanError :: Double
  , evaluationPixelsWithinTolerance :: Double
  , evaluationInkRatio :: Double
  , evaluationPassed :: Bool
  }
  deriving stock (Eq, Show)

-- | The rendering of the source that generated screenshots are compared with.
data Reference
  = -- | Poppler renders the source PDF.
    PopplerReference FilePath
  | -- | Chromium draws the source SVG directly at the given board width and height.
    BrowserReference FilePath (Coordinate BoardSpace) (Coordinate BoardSpace)

data ScaleEvaluation = ScaleEvaluation Int EvaluationResult

data DetailEvaluation = DetailEvaluation Int Int CaptureTile EvaluationResult

referenceDpis :: [Int]
referenceDpis = [detailSelectionDpi, 72]

detailSelectionDpi :: Int
detailSelectionDpi = 18

detailDpis :: [Int]
detailDpis = [288, 576]

detailRegionSide :: Int
detailRegionSide = 32

maximumDetailRegions :: Int
maximumDetailRegions = 3

maximumMeanError :: Double
maximumMeanError = 0.02

minimumPixelsWithinTolerance :: Double
minimumPixelsWithinTolerance = 0.96

minimumInkRatio :: Double
minimumInkRatio = 0.85

maximumInkRatio :: Double
maximumInkRatio = 1.15

pixelTolerance :: Int
pixelTolerance = 32

maximumCaptureWidth :: Int
maximumCaptureWidth = 8192

maximumCaptureHeight :: Int
maximumCaptureHeight = 4096

-- | Evaluation DPIs count board units at 72 per inch, the PDF point.
boardUnitsPerInch :: Int
boardUnitsPerInch = 72

-- | Scratch space for the SVG reference page, removed after evaluation.
referencePageDirectory :: FilePath
referencePageDirectory = ".svg-reference"

runVisualEvaluation :: Reference -> FilePath -> FilePath -> IO (Either BuildError EvaluationResult)
runVisualEvaluation reference siteDirectory reportDirectory = do
  reportExists <- doesPathExist reportDirectory
  if reportExists then removePathForcibly reportDirectory else pure ()
  createDirectoryIfMissing True reportDirectory
  absoluteSite <- makeAbsolute siteDirectory
  absoluteReport <- makeAbsolute reportDirectory
  prepared <- prepareReference reference absoluteReport
  case prepared of
    Left message -> pure (Left (EvaluationError message))
    Right () -> evaluateAll absoluteSite absoluteReport `finally` removeReferencePage absoluteReport
  where
    evaluateAll absoluteSite absoluteReport = do
      evaluated <- evaluateScales absoluteSite absoluteReport referenceDpis
      case evaluated of
        Left buildError -> pure (Left buildError)
        Right scales -> do
          let result = aggregateResults scales
          details <- evaluateDetails reference absoluteSite absoluteReport
          case details of
            Left buildError -> pure (Left buildError)
            Right crops -> writeReports absoluteReport reference scales crops result >> pure (Right result)
    evaluateScales _ _ [] = pure (Right [])
    evaluateScales absoluteSite absoluteReport (dpi : remaining) = do
      evaluated <- evaluateScale reference absoluteSite absoluteReport dpi
      case evaluated of
        Left buildError -> pure (Left buildError)
        Right scale -> fmap (fmap (scale :)) (evaluateScales absoluteSite absoluteReport remaining)

evaluateScale :: Reference -> FilePath -> FilePath -> Int -> IO (Either BuildError ScaleEvaluation)
evaluateScale reference absoluteSite reportDirectory dpi =
  fmap (fmap (ScaleEvaluation dpi . snd)) (renderComparison reference absoluteSite reportDirectory ("-" <> show dpi) dpi Nothing)

renderComparison :: Reference -> FilePath -> FilePath -> String -> Int -> Maybe CaptureTile -> IO (Either BuildError (CaptureTile, EvaluationResult))
renderComparison reference absoluteSite reportDirectory suffix dpi region = do
  let referencePath = reportDirectory </> "reference" <> suffix <> ".png"
      generatedPath = reportDirectory </> "generated" <> suffix <> ".png"
      differencePath = reportDirectory </> "difference" <> suffix <> ".png"
  referenceExit <- renderReference reference reportDirectory dpi region referencePath
  case referenceExit of
    Left message -> pure (Left (EvaluationError message))
    Right () -> do
      referenceDimensions <- readPngDimensions referencePath
      case referenceDimensions of
        Left message -> pure (Left (EvaluationError message))
        Right (width, height) -> do
          let capture = maybe (CaptureTile 0 0 width height) (\tile -> tile {captureWidth = width, captureHeight = height}) region
          browserExit <- runBrowser absoluteSite generatedPath dpi capture
          case browserExit of
            Left message -> pure (Left (EvaluationError message))
            Right () -> fmap (capture,) <$> compareImagePaths referencePath generatedPath differencePath

-- | Render the reference PNG for the whole board, or for an output-pixel region of it.
renderReference :: Reference -> FilePath -> Int -> Maybe CaptureTile -> FilePath -> IO (Either Text ())
renderReference reference reportDirectory dpi region outputPath = case reference of
  -- pdftoppm appends the extension to the output stem itself.
  PopplerReference pdf -> runTool "pdftoppm" (["-singlefile", "-png", "-r", show dpi] <> maybe [] cropArguments region <> [pdf, dropExtension outputPath])
  BrowserReference _ width height -> do
    let board = CaptureTile 0 0 (scaledPixels width) (scaledPixels height)
    case maybe (Just board) (clipToBoard board) region of
      Nothing -> pure (Left "reference region lies outside the board")
      Just capture -> do
        browser <- browserCommand
        capturePage browser (referencePageUrl width height) outputPath capture
  where
    cropArguments (CaptureTile x y width height) = ["-x", show x, "-y", show y, "-W", show width, "-H", show height]
    scaledPixels size = ceiling (unCoordinate size * fromIntegral dpi / fromIntegral boardUnitsPerInch) :: Int
    referencePageUrl width height x y =
      "file://" <> reportDirectory </> referencePageDirectory </> "index.html"
        <> evaluationQuery dpi x y
        <> "&width=" <> show (unCoordinate width)
        <> "&height=" <> show (unCoordinate height)
    clipToBoard (CaptureTile _ _ boardWidth boardHeight) (CaptureTile x y width height)
      | x >= boardWidth || y >= boardHeight = Nothing
      | otherwise = Just (CaptureTile x y (min width (boardWidth - x)) (min height (boardHeight - y)))

prepareReference :: Reference -> FilePath -> IO (Either Text ())
prepareReference reference reportDirectory = case reference of
  PopplerReference _ -> pure (Right ())
  BrowserReference svg _ _ -> do
    let directory = reportDirectory </> referencePageDirectory
    prepared <- try $ do
      createDirectoryIfMissing True directory
      copyFile svg (directory </> "source.svg")
      Text.writeFile (directory </> "index.html") browserReferencePage
    pure (either (\exception -> Left (Text.pack (show (exception :: IOException)))) Right prepared)

removeReferencePage :: FilePath -> IO ()
removeReferencePage reportDirectory = do
  let directory = reportDirectory </> referencePageDirectory
  exists <- doesPathExist directory
  if exists then removePathForcibly directory else pure ()

-- | Draw the copied source SVG at the requested evaluation scale and origin,
-- read from the same URL parameters as the site, without the viewer runtime.
-- A window-sized SVG coordinate window places it, because browsers snap an HTML
-- image box to whole pixels, which would stretch a fractional board. Headless
-- Chromium resizes the window after loading, so the window is placed again.
browserReferencePage :: Text
browserReferencePage =
  Text.unlines
    [ "<!doctype html>"
    , "<html><head><meta charset=\"utf-8\"><style>html,body{margin:0;overflow:hidden;background:white}svg{position:fixed;inset:0;display:block}</style></head>"
    , "<body><svg id=\"reference\" width=\"100%\" height=\"100%\" preserveAspectRatio=\"none\"><image href=\"source.svg\" x=\"0\" y=\"0\"/></svg><script>"
    , "const parameters = new URLSearchParams(location.search);"
    , "const scale = Number(parameters.get('evaluation')) / " <> Text.pack (show boardUnitsPerInch) <> ";"
    , "const reference = document.getElementById('reference');"
    , "const origin = [Number(parameters.get('evaluation-x')), Number(parameters.get('evaluation-y'))];"
    , "const place = () => reference.setAttribute('viewBox', [origin[0] / scale, origin[1] / scale, innerWidth / scale, innerHeight / scale].join(' '));"
    , "place();"
    , "addEventListener('resize', place);"
    , "reference.firstElementChild.setAttribute('width', parameters.get('width'));"
    , "reference.firstElementChild.setAttribute('height', parameters.get('height'));"
    , "</script></body></html>"
    ]

evaluateDetails :: Reference -> FilePath -> FilePath -> IO (Either BuildError [DetailEvaluation])
evaluateDetails reference siteDirectory directory = do
  referenceImage <- readRgb (directory </> "reference-" <> show detailSelectionDpi <> ".png")
  generatedImage <- readRgb (directory </> "generated-" <> show detailSelectionDpi <> ".png")
  case (,) <$> referenceImage <*> generatedImage >>= uncurry selectDetailRegions of
    Left message -> pure (Left (EvaluationError message))
    Right regions -> captureAll [(number, dpi, region) | (number, region) <- zip [1 ..] regions, dpi <- detailDpis]
  where
    captureAll [] = pure (Right [])
    captureAll ((number, dpi, CaptureTile x y width height) : remaining) = do
      let factor = dpi `div` detailSelectionDpi
          region = CaptureTile (x * factor) (y * factor) (width * factor) (height * factor)
          suffix = detailSuffix number dpi
      result <- renderComparison reference siteDirectory directory suffix dpi (Just region)
      case result of
        Left buildError -> pure (Left buildError)
        Right (capture, metrics) -> fmap (fmap (DetailEvaluation number dpi capture metrics :)) (captureAll remaining)

selectDetailRegions :: Image PixelRGB8 -> Image PixelRGB8 -> Either Text [CaptureTile]
selectDetailRegions reference generated
  | dimensions reference /= dimensions generated = Left "detail selection images have different dimensions"
  | otherwise = Right (take maximumDetailRegions (map snd (sortOn (Down . fst) (mapMaybe scored regions))))
  where
    (width, height) = dimensions reference
    regions =
      [ CaptureTile x y (min detailRegionSide (width - x)) (min detailRegionSide (height - y))
      | y <- [0, detailRegionSide .. height - 1]
      , x <- [0, detailRegionSide .. width - 1]
      ]
    left = imageData reference
    right = imageData generated
    scored tile
      | null offsets = Nothing
      | otherwise = Just (sum [sum [channelDifference left right (offset + channel) | channel <- [0 .. 2]] | offset <- offsets], tile)
      where
        offsets =
          [ offset
          | y <- [captureY tile .. captureY tile + captureHeight tile - 1]
          , x <- [captureX tile .. captureX tile + captureWidth tile - 1]
          , let offset = (y * width + x) * 3
          , neutralInk offset
          ]
    neutralInk offset = left Vector.! offset < 255 && left Vector.! offset == left Vector.! (offset + 1) && left Vector.! offset == left Vector.! (offset + 2)

detailSuffix :: Int -> Int -> String
detailSuffix number dpi = "-detail-" <> show number <> "-" <> show dpi

runBrowser :: FilePath -> FilePath -> Int -> CaptureTile -> IO (Either Text ())
runBrowser siteDirectory screenshotPath dpi capture = do
  browser <- browserCommand
  ready <- checkBrowserReady browser
  case ready of
    Left message -> pure (Left message)
    Right () -> capturePage browser sitePageUrl screenshotPath capture
  where
    checkBrowserReady browser = do
      rendered <- runToolOutput browser (browserArguments readinessTile <> ["--dump-dom", readinessUrl])
      pure $ do
        html <- rendered
        if bodyIsReady html then Right () else Left "chromium did not report a completed scene"
    readinessTile = CaptureTile 0 0 1280 720
    readinessUrl = "file://" <> siteDirectory </> "index.html" <> "?evaluation=" <> show dpi <> "&readiness=1"
    sitePageUrl x y = "file://" <> siteDirectory </> "index.html" <> evaluationQuery dpi x y

browserCommand :: IO FilePath
browserCommand = maybe "chromium" id <$> lookupEnv "CHROMIUM"

-- | The evaluation scale and output-pixel origin read by the site and the SVG reference page.
evaluationQuery :: Int -> Int -> Int -> String
evaluationQuery dpi x y = "?evaluation=" <> show dpi <> "&evaluation-x=" <> show x <> "&evaluation-y=" <> show y

-- | Screenshot an output-pixel region of a page, in bounded tiles stitched together when it is large.
capturePage :: FilePath -> (Int -> Int -> String) -> FilePath -> CaptureTile -> IO (Either Text ())
capturePage browser pageUrl screenshotPath (CaptureTile originX originY width height) =
  case captureTiles width height of
    [] -> pure (Left "browser capture dimensions must be positive")
    [tile] -> captureTile tile screenshotPath
    tiles -> captureAndStitch tiles
  where
    captureTile tile path = runTool browser (browserArguments tile <> ["--screenshot=" <> path, pageUrl (originX + captureX tile) (originY + captureY tile)])
    captureAndStitch tiles = do
      attempted <- try $ do
        createDirectoryIfMissing True tileDirectory
        captured <- captureAll tiles
        case captured of
          Left message -> pure (Left message)
          Right () -> do
            stitched <- stitchTileFiles width height [(tile, tilePath tile) | tile <- tiles]
            case stitched of
              Left message -> pure (Left message)
              Right image -> writePngSafely screenshotPath image
      cleaned <- try cleanupTileDirectory
      pure $ case (attempted, cleaned) of
        (Left exception, _) -> Left (Text.pack (show (exception :: IOException)))
        (Right _, Left exception) -> Left (Text.pack (show (exception :: IOException)))
        (Right result, Right ()) -> result
      where
        captureAll [] = pure (Right ())
        captureAll (tile : remaining) = do
          result <- captureTile tile (tilePath tile)
          case result of
            Left message -> pure (Left message)
            Right () -> captureAll remaining
    cleanupTileDirectory = do
      exists <- doesPathExist tileDirectory
      if exists then removePathForcibly tileDirectory else pure ()
    tileDirectory = takeDirectory screenshotPath </> ".capture-tiles"
    tilePath tile = tileDirectory </> takeFileName screenshotPath <> ".tile-" <> show (captureX tile) <> "-" <> show (captureY tile) <> ".png"

browserArguments :: CaptureTile -> [String]
browserArguments tile =
  [ "--headless"
  , "--no-sandbox"
  , "--disable-gpu"
  , "--hide-scrollbars"
  , "--allow-file-access-from-files"
  , "--virtual-time-budget=15000"
  , "--force-device-scale-factor=1"
  , "--window-size=" <> show (captureWidth tile) <> "," <> show (captureHeight tile)
  ]

bodyIsReady :: Text -> Bool
bodyIsReady html =
  not (Text.null body)
    && "data-ready=\"true\"" `Text.isInfixOf` Text.takeWhile (/= '>') body
  where
    body = snd (Text.breakOn "<body" html)

captureTiles :: Int -> Int -> [CaptureTile]
captureTiles width height
  | width <= 0 || height <= 0 = []
  | otherwise =
      [ CaptureTile x y (min maximumCaptureWidth (width - x)) (min maximumCaptureHeight (height - y))
      | y <- [0, maximumCaptureHeight .. height - 1]
      , x <- [0, maximumCaptureWidth .. width - 1]
      ]

stitchTiles :: Int -> Int -> [(CaptureTile, Image PixelRGB8)] -> Either Text (Image PixelRGB8)
stitchTiles width height captures
  | null expected = Left "stitched image dimensions must be positive"
  | map fst captures /= expected = Left "captured tiles do not match the expected grid"
  | any hasWrongDimensions captures = Left "captured tile dimensions do not match the tile plan"
  | otherwise = Right $ runST $ do
      destination <- MutableVector.new (width * height * 3)
      forM_ captures $ \(tile, image) -> copyTile destination width tile image
      pixels <- Vector.unsafeFreeze destination
      pure (Image width height pixels)
  where
    expected = captureTiles width height
    hasWrongDimensions (tile, image) = dimensions image /= (captureWidth tile, captureHeight tile)

stitchTileFiles :: Int -> Int -> [(CaptureTile, FilePath)] -> IO (Either Text (Image PixelRGB8))
stitchTileFiles width height captures
  | map fst captures /= captureTiles width height = pure (Left "captured tiles do not match the expected grid")
  | otherwise = do
      destination <- MutableVector.new (width * height * 3)
      copied <- copyCaptures destination captures
      case copied of
        Left message -> pure (Left message)
        Right () -> do
          pixels <- Vector.unsafeFreeze destination
          pure (Right (Image width height pixels))
  where
    copyCaptures _ [] = pure (Right ())
    copyCaptures destination ((tile, path) : remaining) = do
      decoded <- readRgb path
      case decoded of
        Left message -> pure (Left message)
        Right image
          | dimensions image /= (captureWidth tile, captureHeight tile) -> pure (Left "captured tile dimensions do not match the tile plan")
          | otherwise -> do
              copyTile destination width tile image
              copyCaptures destination remaining

copyTile :: PrimMonad m => MutableVector.MVector (PrimState m) Word8 -> Int -> CaptureTile -> Image PixelRGB8 -> m ()
copyTile destination outputWidth tile image =
  forM_ [0 .. captureHeight tile - 1] $ \row ->
    Vector.copy
      (MutableVector.slice (destinationOffset row) rowLength destination)
      (Vector.slice (row * rowLength) rowLength (imageData image))
  where
    rowLength = captureWidth tile * 3
    destinationOffset row = ((captureY tile + row) * outputWidth + captureX tile) * 3

runTool :: FilePath -> [String] -> IO (Either Text ())
runTool command arguments = do
  result <- runProcess command arguments
  pure $ case result of
    Left exception -> Left (Text.pack (command <> " failed: " <> show exception))
    Right (ExitSuccess, _, _) -> Right ()
    Right (_, _, standardError) -> Left (Text.pack (command <> " failed: " <> standardError))

runToolOutput :: FilePath -> [String] -> IO (Either Text Text)
runToolOutput command arguments = do
  result <- runProcess command arguments
  pure $ case result of
    Left exception -> Left (Text.pack (command <> " failed: " <> show exception))
    Right (ExitSuccess, standardOutput, _) -> Right (Text.pack standardOutput)
    Right (_, _, standardError) -> Left (Text.pack (command <> " failed: " <> standardError))

runProcess :: FilePath -> [String] -> IO (Either IOException (ExitCode, String, String))
runProcess command arguments = try (readProcessWithExitCode command arguments "")

readPngDimensions :: FilePath -> IO (Either Text (Int, Int))
readPngDimensions path = do
  header <- tryReadHeader path
  pure $ case header of
    Left exception -> Left (Text.pack (path <> " could not be read: " <> show exception))
    Right bytes -> parsePngDimensions bytes

tryReadHeader :: FilePath -> IO (Either IOException ByteString.ByteString)
tryReadHeader path = try (withBinaryFile path ReadMode (`ByteString.hGet` 24))

parsePngDimensions :: ByteString.ByteString -> Either Text (Int, Int)
parsePngDimensions header
  | ByteString.length header /= 24 = Left "PNG header is incomplete"
  | ByteString.take 8 header /= ByteString.pack [137, 80, 78, 71, 13, 10, 26, 10] = Left "image does not have a PNG signature"
  | ByteString.take 8 (ByteString.drop 8 header) /= ByteString.pack [0, 0, 0, 13, 73, 72, 68, 82] = Left "PNG does not start with an IHDR chunk"
  | width <= 0 || height <= 0 = Left "PNG dimensions must be positive"
  | otherwise = Right (width, height)
  where
    width = word32At 16
    height = word32At 20
    word32At offset =
      fromIntegral (ByteString.index header offset) * 16777216
        + fromIntegral (ByteString.index header (offset + 1)) * 65536
        + fromIntegral (ByteString.index header (offset + 2)) * 256
        + fromIntegral (ByteString.index header (offset + 3))

readRgb :: FilePath -> IO (Either Text (Image PixelRGB8))
readRgb path = do
  decoded <- tryReadImage path
  pure $ case decoded of
    Left exception -> Left (Text.pack (path <> " could not be read: " <> show exception))
    Right result -> either (Left . Text.pack) (Right . convertRGB8) result

tryReadImage :: FilePath -> IO (Either IOException (Either String DynamicImage))
tryReadImage = try . readImage

writePngSafely :: FilePath -> Image PixelRGB8 -> IO (Either Text ())
writePngSafely path image = do
  written <- tryWritePng path image
  pure (either (Left . Text.pack . show) Right written)

tryWritePng :: FilePath -> Image PixelRGB8 -> IO (Either IOException ())
tryWritePng path = try . writePng path

compareImagePaths :: FilePath -> FilePath -> FilePath -> IO (Either BuildError EvaluationResult)
compareImagePaths referencePath generatedPath differencePath = do
  reference <- readRgb referencePath
  case reference of
    Left message -> pure (Left (EvaluationError message))
    Right image -> compareImages image generatedPath differencePath

compareImages :: Image PixelRGB8 -> FilePath -> FilePath -> IO (Either BuildError EvaluationResult)
compareImages reference generatedPath differencePath = do
  generated <- readRgb generatedPath
  case generated of
    Left message -> pure (Left (EvaluationError message))
    Right generatedImage
      | dimensions reference /= dimensions generatedImage ->
          pure (Left (EvaluationError "reference and generated screenshots have different dimensions"))
      | otherwise -> do
          let result = calculateDifference reference generatedImage
              difference = differenceImage reference generatedImage
          writePng differencePath difference
          pure (Right result)

aggregateResults :: [ScaleEvaluation] -> EvaluationResult
aggregateResults scales =
  EvaluationResult
    { evaluationMeanError = maximum (map (evaluationMeanError . scaleResult) scales)
    , evaluationPixelsWithinTolerance = minimum (map (evaluationPixelsWithinTolerance . scaleResult) scales)
    , evaluationInkRatio = evaluationInkRatio (maximumByInkDistance (map scaleResult scales))
    , evaluationPassed = all (evaluationPassed . scaleResult) scales
    }
  where
    scaleResult (ScaleEvaluation _ result) = result
    maximumByInkDistance (first : rest) = foldl choose first rest
    maximumByInkDistance [] = EvaluationResult 1 0 0 False
    choose left right
      | abs (evaluationInkRatio right - 1) > abs (evaluationInkRatio left - 1) = right
      | otherwise = left

calculateDifference :: Image PixelRGB8 -> Image PixelRGB8 -> EvaluationResult
calculateDifference reference generated =
  EvaluationResult meanError withinRatio inkRatio passed
  where
    referenceData = imageData reference
    generatedData = imageData generated
    totalDifference = Vector.ifoldl' (\total index left -> total + abs (fromIntegral left - fromIntegral (generatedData Vector.! index) :: Int)) 0 referenceData
    channelCount = Vector.length referenceData
    meanError = fromIntegral totalDifference / fromIntegral (channelCount * 255)
    pixelCount = imageWidth reference * imageHeight reference
    withinCount = countPixelsWithin reference generated pixelCount
    withinRatio = fromIntegral withinCount / fromIntegral pixelCount
    referenceInk = imageInk reference
    generatedInk = imageInk generated
    inkRatio = if referenceInk == 0 then if generatedInk == 0 then 1 else 0 else generatedInk / referenceInk
    passed =
      meanError <= maximumMeanError
        && withinRatio >= minimumPixelsWithinTolerance
        && inkRatio >= minimumInkRatio
        && inkRatio <= maximumInkRatio

imageInk :: Image PixelRGB8 -> Double
imageInk = fromIntegral . Vector.foldl' (\total channel -> total + (255 - fromIntegral channel :: Integer)) 0 . imageData

countPixelsWithin :: Image PixelRGB8 -> Image PixelRGB8 -> Int -> Int
countPixelsWithin reference generated pixelCount = go 0 0
  where
    left = imageData reference
    right = imageData generated
    go pixel matched
      | pixel == pixelCount = matched
      | otherwise =
          let offset = pixel * 3
              maximumDifference = maximum [channelDifference left right offset, channelDifference left right (offset + 1), channelDifference left right (offset + 2)]
           in go (pixel + 1) (if maximumDifference <= pixelTolerance then matched + 1 else matched)

channelDifference :: Vector.Vector Word8 -> Vector.Vector Word8 -> Int -> Int
channelDifference left right index = abs (fromIntegral (left Vector.! index) - fromIntegral (right Vector.! index) :: Int)

differenceImage :: Image PixelRGB8 -> Image PixelRGB8 -> Image PixelRGB8
differenceImage reference generated =
  generateImage pixel (imageWidth reference) (imageHeight reference)
  where
    left = imageData reference
    right = imageData generated
    pixel x y =
      let offset = (y * imageWidth reference + x) * 3
       in PixelRGB8
            (differenceChannel left right offset)
            (differenceChannel left right (offset + 1))
            (differenceChannel left right (offset + 2))

differenceChannel :: Vector.Vector Word8 -> Vector.Vector Word8 -> Int -> Word8
differenceChannel left right index = fromIntegral (min 255 (channelDifference left right index * 4))

dimensions :: Image pixel -> (Int, Int)
dimensions image = (imageWidth image, imageHeight image)

writeReports :: FilePath -> Reference -> [ScaleEvaluation] -> [DetailEvaluation] -> EvaluationResult -> IO ()
writeReports directory reference scales details result = do
  LazyByteString.writeFile (directory </> "evaluation.json") json
  Text.writeFile (directory </> "report.html") html
  where
    json =
      encode
        ( object
            [ "reference" .= referenceRenderer reference
            , "meanError" .= evaluationMeanError result
            , "pixelsWithinTolerance" .= evaluationPixelsWithinTolerance result
            , "inkRatio" .= evaluationInkRatio result
            , "maximumMeanError" .= maximumMeanError
            , "minimumPixelsWithinTolerance" .= minimumPixelsWithinTolerance
            , "minimumInkRatio" .= minimumInkRatio
            , "maximumInkRatio" .= maximumInkRatio
            , "pixelTolerance" .= pixelTolerance
            , "passed" .= evaluationPassed result
            , "scales" .= map scaleJson scales
            , "details" .= map detailJson details
            ]
        )
    html =
      Text.unlines
        [ "<!doctype html><html><body><h1>Visual evaluation</h1>"
        , "<p>Reference: " <> referenceRenderer reference <> "</p>"
        , "<p>Mean normalized channel error: " <> Text.pack (show (evaluationMeanError result)) <> "</p>"
        , "<p>Pixels within tolerance: " <> Text.pack (show (evaluationPixelsWithinTolerance result)) <> "</p>"
        , "<p>Generated/reference ink ratio: " <> Text.pack (show (evaluationInkRatio result)) <> "</p>"
        , "<p>Passed: " <> Text.pack (show (evaluationPassed result)) <> "</p>"
        , foldMap scaleHtml scales
        , "<h2>Zoom details: inspection evidence</h2><p>These sampled crops do not contribute to the whole-board pass thresholds.</p>"
        , foldMap detailHtml details
        , "</body></html>"
        ]
    scaleJson (ScaleEvaluation dpi scale) =
      object
        [ "dpi" .= dpi
        , "meanError" .= evaluationMeanError scale
        , "pixelsWithinTolerance" .= evaluationPixelsWithinTolerance scale
        , "inkRatio" .= evaluationInkRatio scale
        , "passed" .= evaluationPassed scale
        ]
    scaleHtml (ScaleEvaluation dpi scale) =
      Text.unlines
        [ "<h2>" <> Text.pack (show dpi) <> " DPI</h2>"
        , "<p>Mean error: " <> Text.pack (show (evaluationMeanError scale)) <> "; pixels within tolerance: " <> Text.pack (show (evaluationPixelsWithinTolerance scale)) <> "; ink ratio: " <> Text.pack (show (evaluationInkRatio scale)) <> "</p>"
        , "<img src=\"reference-" <> Text.pack (show dpi) <> ".png\" width=\"32%\" alt=\"Reference at " <> Text.pack (show dpi) <> " DPI\">"
        , "<img src=\"generated-" <> Text.pack (show dpi) <> ".png\" width=\"32%\" alt=\"Generated at " <> Text.pack (show dpi) <> " DPI\">"
        , "<img src=\"difference-" <> Text.pack (show dpi) <> ".png\" width=\"32%\" alt=\"Difference at " <> Text.pack (show dpi) <> " DPI\">"
        ]
    detailJson (DetailEvaluation number dpi region metrics) =
      object
        [ "number" .= number
        , "dpi" .= dpi
        , "x" .= captureX region
        , "y" .= captureY region
        , "width" .= captureWidth region
        , "height" .= captureHeight region
        , "inspectionOnly" .= True
        , "meanError" .= evaluationMeanError metrics
        , "pixelsWithinTolerance" .= evaluationPixelsWithinTolerance metrics
        , "inkRatio" .= evaluationInkRatio metrics
        ]
    detailHtml (DetailEvaluation number dpi region metrics) =
      let suffix = Text.pack (detailSuffix number dpi)
       in Text.unlines
            [ "<h3>Detail " <> Text.pack (show number) <> " at " <> Text.pack (show dpi) <> " DPI</h3>"
            , "<p>Output-pixel origin: " <> Text.pack (show (captureX region, captureY region)) <> "; mean error: " <> Text.pack (show (evaluationMeanError metrics)) <> "; ink ratio: " <> Text.pack (show (evaluationInkRatio metrics)) <> "</p>"
            , "<img src=\"reference" <> suffix <> ".png\" width=\"32%\" alt=\"Reference detail\">"
            , "<img src=\"generated" <> suffix <> ".png\" width=\"32%\" alt=\"Generated detail\">"
            , "<img src=\"difference" <> suffix <> ".png\" width=\"32%\" alt=\"Difference detail\">"
            ]

referenceRenderer :: Reference -> Text
referenceRenderer reference = case reference of
  PopplerReference _ -> "Poppler rendering of the source PDF"
  BrowserReference {} -> "Chromium rendering of the source SVG"
