{-# LANGUAGE OverloadedStrings #-}

-- | Produce evidence for the software-factory feedback loop.
--
-- The deployed page never uses a rendered PDF. During development, however,
-- a mature renderer is a useful oracle. We compare that oracle with a browser
-- screenshot of our generated DOM/SVG scene and keep the difference image
-- as evidence for the next parser iteration.
module Factory.Evaluation
  ( CaptureTile (..)
  , EvaluationResult (..)
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
import Control.Exception (IOException, try)
import Control.Monad (forM_)
import Control.Monad.Primitive (PrimMonad, PrimState)
import Control.Monad.ST (runST)
import Data.Aeson (encode, object, (.=))
import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Data.Ord (Down (Down))
import Data.Text (Text)
import Data.Word (Word8)
import Factory.Domain (BuildError (EvaluationError))
import System.Directory (createDirectoryIfMissing, doesPathExist, makeAbsolute, removePathForcibly)
import System.Exit (ExitCode (ExitSuccess))
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, takeFileName, (</>))
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

runVisualEvaluation :: FilePath -> FilePath -> FilePath -> IO (Either BuildError EvaluationResult)
runVisualEvaluation pdfPath siteDirectory reportDirectory = do
  reportExists <- doesPathExist reportDirectory
  if reportExists then removePathForcibly reportDirectory else pure ()
  createDirectoryIfMissing True reportDirectory
  absoluteSite <- makeAbsolute siteDirectory
  evaluated <- evaluateScales absoluteSite referenceDpis
  case evaluated of
    Left buildError -> pure (Left buildError)
    Right scales -> do
      let result = aggregateResults scales
      details <- evaluateDetails pdfPath absoluteSite reportDirectory
      case details of
        Left buildError -> pure (Left buildError)
        Right crops -> writeReports reportDirectory scales crops result >> pure (Right result)
  where
    evaluateScales _ [] = pure (Right [])
    evaluateScales absoluteSite (dpi : remaining) = do
      evaluated <- evaluateScale pdfPath absoluteSite reportDirectory dpi
      case evaluated of
        Left buildError -> pure (Left buildError)
        Right scale -> fmap (fmap (scale :)) (evaluateScales absoluteSite remaining)

evaluateScale :: FilePath -> FilePath -> FilePath -> Int -> IO (Either BuildError ScaleEvaluation)
evaluateScale pdfPath absoluteSite reportDirectory dpi =
  fmap (fmap (ScaleEvaluation dpi . snd)) (renderComparison pdfPath absoluteSite reportDirectory ("-" <> show dpi) dpi Nothing)

renderComparison :: FilePath -> FilePath -> FilePath -> String -> Int -> Maybe CaptureTile -> IO (Either BuildError (CaptureTile, EvaluationResult))
renderComparison pdfPath absoluteSite reportDirectory suffix dpi region = do
  let referenceStem = reportDirectory </> "reference" <> suffix
      referencePath = referenceStem <> ".png"
      generatedPath = reportDirectory </> "generated" <> suffix <> ".png"
      differencePath = reportDirectory </> "difference" <> suffix <> ".png"
      cropArguments (CaptureTile x y width height) = ["-x", show x, "-y", show y, "-W", show width, "-H", show height]
  referenceExit <- runTool "pdftoppm" (["-singlefile", "-png", "-r", show dpi] <> maybe [] cropArguments region <> [pdfPath, referenceStem])
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

evaluateDetails :: FilePath -> FilePath -> FilePath -> IO (Either BuildError [DetailEvaluation])
evaluateDetails pdfPath siteDirectory directory = do
  reference <- readRgb (directory </> "reference-" <> show detailSelectionDpi <> ".png")
  generated <- readRgb (directory </> "generated-" <> show detailSelectionDpi <> ".png")
  case (,) <$> reference <*> generated >>= uncurry selectDetailRegions of
    Left message -> pure (Left (EvaluationError message))
    Right regions -> captureAll [(number, dpi, region) | (number, region) <- zip [1 ..] regions, dpi <- detailDpis]
  where
    captureAll [] = pure (Right [])
    captureAll ((number, dpi, CaptureTile x y width height) : remaining) = do
      let factor = dpi `div` detailSelectionDpi
          region = CaptureTile (x * factor) (y * factor) (width * factor) (height * factor)
          suffix = detailSuffix number dpi
      result <- renderComparison pdfPath siteDirectory directory suffix dpi (Just region)
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
runBrowser siteDirectory screenshotPath dpi (CaptureTile originX originY width height) = do
  browser <- maybe "chromium" id <$> lookupEnv "CHROMIUM"
  case captureTiles width height of
    [] -> pure (Left "browser capture dimensions must be positive")
    tiles -> do
      ready <- checkBrowserReady browser
      case ready of
        Left message -> pure (Left message)
        Right ()
          | [tile] <- tiles -> runTool browser (browserArguments tile <> ["--screenshot=" <> screenshotPath, pageUrl tile])
          | otherwise -> captureAndStitch browser tiles
  where
    checkBrowserReady browser = do
      rendered <- runToolOutput browser (browserArguments readinessTile <> ["--dump-dom", readinessUrl])
      pure $ do
        html <- rendered
        if bodyIsReady html then Right () else Left "chromium did not report a completed scene"
    readinessTile = CaptureTile 0 0 1280 720
    readinessUrl = "file://" <> siteDirectory </> "index.html" <> "?evaluation=" <> show dpi <> "&readiness=1"
    captureAndStitch browser tiles = do
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
          result <- captureTile tile
          case result of
            Left message -> pure (Left message)
            Right () -> captureAll remaining
        captureTile tile = runTool browser (browserArguments tile <> ["--screenshot=" <> tilePath tile, pageUrl tile])
    cleanupTileDirectory = do
      exists <- doesPathExist tileDirectory
      if exists then removePathForcibly tileDirectory else pure ()
    tileDirectory = takeDirectory screenshotPath </> ".capture-tiles"
    tilePath tile = tileDirectory </> takeFileName screenshotPath <> ".tile-" <> show (captureX tile) <> "-" <> show (captureY tile) <> ".png"
    pageUrl tile =
      "file://"
        <> siteDirectory </> "index.html"
        <> "?evaluation=" <> show dpi
        <> "&evaluation-x=" <> show (originX + captureX tile)
        <> "&evaluation-y=" <> show (originY + captureY tile)
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

writeReports :: FilePath -> [ScaleEvaluation] -> [DetailEvaluation] -> EvaluationResult -> IO ()
writeReports directory scales details result = do
  LazyByteString.writeFile (directory </> "evaluation.json") json
  Text.writeFile (directory </> "report.html") html
  where
    json =
      encode
        ( object
            [ "meanError" .= evaluationMeanError result
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
        [ "<!doctype html><html><body><h1>Parser evaluation</h1>"
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
