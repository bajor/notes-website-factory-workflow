{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The effectful boundary around the Haskell PDF library.
--
-- pdf-toolbox understands files, references, dictionaries, and compressed
-- streams. This module translates those low-level values into our small
-- domain. Everything after this module is independent of PDF internals.
module Factory.Pdf
  ( ParsedPdf (..)
  , PdfSummary (..)
  , classifyUrl
  , parsePdf
  , rejectDecode
  , rgbaImage
  ) where

import Codec.Picture (Image, PixelRGBA8 (PixelRGBA8), generateImage, writePng)
import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM, unless, when)
import Control.Monad.Except (ExceptT, liftEither, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Foldable (traverse_)
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Set (Set)
import Data.Text (Text)
import Factory.Domain
import Factory.Geometry (rectangleToBoard)
import Factory.Interpreter (ColorSpaceResource (..), Resources (Resources), VisualResource (..), interpretOperators)
import Factory.Vectorize (ImageDisposition (..), classifyImage, opaqueHighlighter, traceImage)
import Network.URI (URI (uriAuthority, uriFragment, uriPath, uriQuery, uriScheme), URIAuth (uriPort, uriRegName, uriUserInfo), parseURI)
import Pdf.Content (Expr, Operator, parseContent, readNextOperator)
import Pdf.Core
  ( Array
  , Dict
  , Name
  , Object (Array, Name, Ref, Stream)
  , Ref
  , Stream (S)
  )
import Pdf.Core.Name (toByteString)
import Pdf.Core.Object.Util (arrayValue, dictValue, intValue, nameValue, realValue, stringValue)
import Pdf.Core.Types (Rectangle (Rectangle))
import Pdf.Document
  ( Pdf
  , catalogPageNode
  , document
  , documentCatalog
  , enableCache
  , lookupObject
  , pageContents
  , pageMediaBox
  , pageNodeNKids
  , pageNodePageByNum
  , rawStreamContent
  , streamContent
  , withPdfFile
  )
import Pdf.Document.Internal.Types (Page (Page))
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeFileName, (</>))
import qualified Data.ByteString as ByteString
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Vector as Vector
import qualified System.IO.Streams as Streams
import qualified System.IO.Streams.Attoparsec.ByteString as Streams.Attoparsec

data PdfSummary = PdfSummary
  { summaryPageCount :: Int
  , summaryOperatorCount :: Int
  , summaryImageCount :: Int
  , summaryVectorCount :: Int
  , summaryRasterCount :: Int
  , summaryLinkCount :: Int
  , summaryWidth :: Double
  , summaryHeight :: Double
  }
  deriving stock (Eq, Show)

type PdfAction = ExceptT BuildError IO

data PreparedImage
  = PreparedJpeg Asset ByteString
  | PreparedPng Asset (Image PixelRGBA8)
  | PreparedVector [VectorShape]

data ParsedPdf = ParsedPdf
  { parsedScene :: Scene 'Unvalidated
  , parsedSummary :: PdfSummary
  }

preparedResource :: PreparedImage -> VisualResource
preparedResource prepared = case prepared of
  PreparedJpeg asset _ -> RasterResource (assetId asset)
  PreparedPng asset _ -> RasterResource (assetId asset)
  PreparedVector shapes -> VectorResource shapes

preparedAsset :: PreparedImage -> Maybe Asset
preparedAsset prepared = case prepared of
  PreparedJpeg asset _ -> Just asset
  PreparedPng asset _ -> Just asset
  PreparedVector _ -> Nothing

parsePdf :: FilePath -> FilePath -> IO (Either BuildError ParsedPdf)
parsePdf pdfPath assetDirectory = do
  result <- try (withPdfFile pdfPath (runExceptT . parseOpenPdf assetDirectory))
  pure $ case result of
    Left exception -> Left (IoError (Text.pack (displayException (exception :: SomeException))))
    Right parsed -> parsed

parseOpenPdf :: FilePath -> Pdf -> PdfAction ParsedPdf
parseOpenPdf assetDirectory pdf = do
  liftIO (enableCache pdf)
  rootPages <- liftIO (document pdf >>= documentCatalog >>= catalogPageNode)
  pageCount <- liftIO (pageNodeNKids rootPages)
  unless (pageCount == 1) (throwError (PageCountError pageCount))
  page@(Page _ _ pageDictionary) <- liftIO (pageNodePageByNum rootPages 0)
  (width, height) <- pageDimensions page
  resources <- requireResolvedDict pdf pageDictionary "Resources"
  preparedImages <- prepareImages pdf resources
  alphaMap <- extractAlphaStates pdf resources
  colorSpaceMap <- extractColorSpaces pdf resources
  operators <- readPageOperators pdf page
  let imageMap = Map.map preparedResource preparedImages
  contentNodes <- liftEither (interpretOperators (Coordinate height) (Resources imageMap alphaMap colorSpaceMap) operators)
  links <- extractLinks pdf pageDictionary (Coordinate height)
  let referencedAssets = Set.fromList [identifier | ImageNode identifier _ _ _ <- contentNodes]
      usedImages = filter (isUsedRaster referencedAssets) (Map.elems preparedImages)
  assets <- materializeImages assetDirectory usedImages
  let vectorCount = length (filter isPreparedVector (Map.elems preparedImages))
      rasterCount = length assets
  let scene =
        Scene
          { sceneWidth = Coordinate width
          , sceneHeight = Coordinate height
          , sceneAssets = assets
          , sceneContent = contentNodes <> links
          }
      summary = PdfSummary 1 (length operators) (Map.size preparedImages) vectorCount rasterCount (length links) width height
  pure (ParsedPdf scene summary)

isPreparedVector :: PreparedImage -> Bool
isPreparedVector PreparedVector {} = True
isPreparedVector _ = False

isUsedRaster :: Set AssetId -> PreparedImage -> Bool
isUsedRaster referenced prepared = case preparedAsset prepared of
  Just asset -> Set.member (assetId asset) referenced
  Nothing -> True

pageDimensions :: Page -> PdfAction (Double, Double)
pageDimensions page = do
  Rectangle x1 y1 x2 y2 <- liftIO (pageMediaBox page)
  let width = x2 - x1
      height = y2 - y1
  when (width <= 0 || height <= 0) (throwError (PdfStructureError "page dimensions must be positive"))
  pure (width, height)

readPageOperators :: Pdf -> Page -> PdfAction [Operator]
readPageOperators pdf page = do
  references <- liftIO (pageContents page)
  chunks <- traverse (readOperatorStream pdf) references
  pure (concat chunks)

readOperatorStream :: Pdf -> Ref -> PdfAction [Operator]
readOperatorStream pdf reference = do
  object <- liftIO (lookupObject pdf reference)
  case object of
    Stream stream -> do
      bytes <- liftIO (streamContent pdf reference stream)
      expressions <- liftIO (Streams.Attoparsec.parserToInputStream parseContent bytes)
      liftIO (collectOperators expressions [])
    _ -> throwError (PdfStructureError "page content reference does not point to a stream")

collectOperators :: Streams.InputStream Expr -> [Operator] -> IO [Operator]
collectOperators expressions reversed = do
  next <- readNextOperator expressions
  case next of
    Nothing -> pure (reverse reversed)
    Just operator -> collectOperators expressions (operator : reversed)

prepareImages :: Pdf -> Dict -> PdfAction (Map Name PreparedImage)
prepareImages pdf resources = do
  xobjects <- optionalResolvedDict pdf resources "XObject"
  extracted <- forM (sortOn (nameText . fst) (HashMap.toList xobjects)) $ \(resourceName, object) -> do
    resolved <- resolveWithReference pdf object
    case resolved of
      Just (reference, Stream stream@(S dictionary _))
        | HashMap.lookup "Subtype" dictionary == Just (Name "Image") -> do
            prepared <- prepareImage pdf resourceName reference stream dictionary
            pure (Just (resourceName, prepared))
      _ -> pure Nothing
  pure (Map.fromList (catMaybes extracted))

prepareImage :: Pdf -> Name -> Ref -> Stream -> Dict -> PdfAction PreparedImage
prepareImage pdf resourceName reference stream dictionary = do
  width <- requireInt dictionary "Width"
  height <- requireInt dictionary "Height"
  bits <- requireInt dictionary "BitsPerComponent"
  unless (bits == 8) (throwError (UnsupportedImage "only 8-bit image components are supported"))
  liftEither (rejectDecode (HashMap.lookup "Decode" dictionary))
  components <- imageComponents pdf dictionary
  filterName <- requireName dictionary "Filter"
  let baseName = Text.unpack (nameText resourceName)
      identifier = AssetId (nameText resourceName)
  case nameText filterName of
    "DCTDecode" -> do
      when (HashMap.member "SMask" dictionary) (throwError (UnsupportedImage "JPEG images with soft masks are not supported"))
      bytes <- readRawStream pdf reference stream
      let fileName = baseName <> ".jpg"
      pure (PreparedJpeg (Asset identifier ("assets/" <> fileName) width height) bytes)
    "FlateDecode" -> do
      colorBytes <- readDecodedStream pdf reference stream
      alphaBytes <- readSoftMask pdf dictionary width height
      image <- liftEither (rgbaImage width height components colorBytes alphaBytes)
      disposition <- case classifyImage alphaBytes of
        Left (UnsupportedImage message) -> throwError (UnsupportedImage (nameText resourceName <> ": " <> message))
        Left buildError -> throwError buildError
        Right classified -> pure classified
      case disposition of
        PreserveRaster ->
          let fileName = baseName <> ".png"
           in pure (PreparedPng (Asset identifier ("assets/" <> fileName) width height) image)
        PreserveLowAlphaRaster ->
          let fileName = baseName <> ".png"
              outputImage = fromMaybe image (opaqueHighlighter image)
           in pure (PreparedPng (Asset identifier ("assets/" <> fileName) width height) outputImage)
        TraceAsVector -> PreparedVector <$> liftEither (traceImage image)
    unsupported -> throwError (UnsupportedImage ("unsupported image filter: " <> unsupported))

materializeImages :: FilePath -> [PreparedImage] -> PdfAction [Asset]
materializeImages assetDirectory preparedImages = do
  let assets = catMaybes (map preparedAsset preparedImages)
  unless (null assets) (liftIO (createDirectoryIfMissing True assetDirectory))
  traverse_ writePrepared preparedImages
  pure assets
  where
    writePrepared prepared = case prepared of
      PreparedJpeg asset bytes -> liftIO (ByteString.writeFile (assetPath asset) bytes)
      PreparedPng asset image -> liftIO (writePng (assetPath asset) image)
      PreparedVector _ -> pure ()
    assetPath asset = assetDirectory </> takeFileName (assetFile asset)

readSoftMask :: Pdf -> Dict -> Int -> Int -> PdfAction (Maybe ByteString)
readSoftMask pdf dictionary width height = case HashMap.lookup "SMask" dictionary of
  Nothing -> pure Nothing
  Just object -> do
    resolved <- resolveWithReference pdf object
    case resolved of
      Just (reference, Stream stream@(S maskDictionary _)) -> do
        maskWidth <- requireInt maskDictionary "Width"
        maskHeight <- requireInt maskDictionary "Height"
        unless (maskWidth == width && maskHeight == height) (throwError (UnsupportedImage "soft-mask dimensions differ from the image"))
        liftEither (rejectDecode (HashMap.lookup "Decode" maskDictionary))
        Just <$> readDecodedStream pdf reference stream
      _ -> throwError (UnsupportedImage "SMask does not reference an image stream")

imageComponents :: Pdf -> Dict -> PdfAction Int
imageComponents pdf dictionary = do
  colorSpaceObject <- requireKey dictionary "ColorSpace"
  colorSpace <- supportedDeviceColorSpace pdf colorSpaceObject
  case colorSpace of
    Just GrayColorSpace -> pure 1
    Just RgbColorSpace -> pure 3
    _ -> throwError (UnsupportedImage "unsupported image color space")

rgbaImage :: Int -> Int -> Int -> ByteString -> Maybe ByteString -> Either BuildError (Image PixelRGBA8)
rgbaImage width height components colorBytes alphaBytes = do
  let pixels = width * height
  when (components `notElem` [1, 3]) (Left (UnsupportedImage "decoded image samples are not RGB or grayscale"))
  when (ByteString.length colorBytes /= pixels * components) (Left (UnsupportedImage "decoded image samples have the wrong length"))
  case alphaBytes of
    Just alpha -> when (ByteString.length alpha /= pixels) (Left (UnsupportedImage "decoded soft mask has the wrong length"))
    Nothing -> Right ()
  Right (generateImage pixelAt width height)
  where
    pixelAt x y =
      let index = y * width + x
          alpha = maybe 255 (`ByteString.index` index) alphaBytes
       in if components == 3
            then
              PixelRGBA8
                (ByteString.index colorBytes (index * 3))
                (ByteString.index colorBytes (index * 3 + 1))
                (ByteString.index colorBytes (index * 3 + 2))
                alpha
            else
              let gray = ByteString.index colorBytes index
               in PixelRGBA8 gray gray gray alpha

rejectDecode :: Maybe Object -> Either BuildError ()
rejectDecode Nothing = Right ()
rejectDecode (Just _) = Left (UnsupportedImage "image Decode arrays are not supported")

extractAlphaStates :: Pdf -> Dict -> PdfAction (Map Name Double)
extractAlphaStates pdf resources = do
  states <- optionalResolvedDict pdf resources "ExtGState"
  pairs <- forM (HashMap.toList states) $ \(name, object) -> do
    dictionary <- resolvedDict pdf object "ExtGState entry"
    let opacity = fromMaybe 1 (HashMap.lookup "ca" dictionary >>= realValue)
    pure (name, opacity)
  pure (Map.fromList pairs)

extractColorSpaces :: Pdf -> Dict -> PdfAction (Map Name ColorSpaceResource)
extractColorSpaces pdf resources = do
  colorSpaces <- optionalResolvedDict pdf resources "ColorSpace"
  pairs <- forM (sortOn (nameText . fst) (HashMap.toList colorSpaces)) $ \(name, object) -> do
    colorSpace <- supportedDeviceColorSpace pdf object
    pure (name, maybe UnsupportedColorSpace SupportedColorSpace colorSpace)
  pure (Map.fromList pairs)

supportedDeviceColorSpace :: Pdf -> Object -> PdfAction (Maybe DeviceColorSpace)
supportedDeviceColorSpace pdf object = do
  colorSpace <- resolve pdf object
  case colorSpace of
    Name "DeviceGray" -> pure (Just GrayColorSpace)
    Name "DeviceRGB" -> pure (Just RgbColorSpace)
    Name "DeviceCMYK" -> pure (Just CmykColorSpace)
    Array values -> case Vector.toList values of
      [Name "ICCBased", profileObject] -> do
        resolvedProfile <- resolve pdf profileObject
        profile <- case resolvedProfile of
          Stream (S profileDictionary _) -> pure profileDictionary
          profileValue -> requireDict "ICCBased color profile" profileValue
        components <- requireInt profile "N"
        pure $ case components of
          1 -> Just GrayColorSpace
          3 -> Just RgbColorSpace
          _ -> Nothing
      _ -> pure Nothing
    _ -> pure Nothing

extractLinks :: Pdf -> Dict -> Coordinate PdfSpace -> PdfAction [SceneNode]
extractLinks pdf pageDictionary pageHeight = case HashMap.lookup "Annots" pageDictionary of
  Nothing -> pure []
  Just object -> do
    annotationArray <- resolve pdf object >>= requireArray "Annots"
    catMaybes <$> traverse (extractLink pdf pageHeight) (Vector.toList annotationArray)

extractLink :: Pdf -> Coordinate PdfSpace -> Object -> PdfAction (Maybe SceneNode)
extractLink pdf pageHeight object = do
  annotation <- resolvedDict pdf object "annotation"
  if HashMap.lookup "Subtype" annotation /= Just (Name "Link")
    then pure Nothing
    else do
      actionObject <- requireKey annotation "A"
      action <- resolvedDict pdf actionObject "link action"
      unless (HashMap.lookup "S" action == Just (Name "URI")) (throwError (InvalidUrl "link action is not a URI"))
      uriObject <- requireKey action "URI" >>= resolve pdf
      uriBytes <- maybe (throwError (InvalidUrl "URI is not a PDF string")) pure (stringValue uriObject)
      target <- liftEither (classifyUrl (Text.decodeLatin1 uriBytes))
      rectangleObject <- requireKey annotation "Rect" >>= resolve pdf
      rectangle <- pdfRectangle rectangleObject
      pure (Just (LinkNode target (rectangleToBoard pageHeight rectangle)))

classifyUrl :: Text -> Either BuildError LinkTarget
classifyUrl raw = case parseURI (Text.unpack raw) of
  Nothing -> Left (InvalidUrl ("invalid URI: " <> raw))
  Just uri
    | uriScheme uri `notElem` ["http:", "https:"] -> Left (InvalidUrl ("unsupported URI scheme: " <> raw))
    | isGameUri uri -> Right (Game (GameUrl raw))
    | otherwise -> maybe (Right (External (WebUrl raw))) (Right . YouTube . VideoId) (youtubeId uri)

isGameUri :: URI -> Bool
isGameUri uri = case uriAuthority uri of
  Nothing -> False
  Just authority ->
    uriScheme uri == "https:"
      && null (uriUserInfo authority)
      && null (uriPort authority)
      && Text.toLower (Text.pack (uriRegName authority)) == "bajor.github.io"
      && uriPath uri == "/algo-arcade/"
      && maybe False (not . Text.null) (Text.stripPrefix "#/games/" (Text.pack (uriFragment uri)))

youtubeId :: URI -> Maybe Text
youtubeId uri = do
  authority <- uriAuthority uri
  let host = Text.toLower (Text.pack (uriRegName authority))
      pathParts = filter (not . Text.null) (Text.splitOn "/" (Text.pack (uriPath uri)))
      candidate
        | host == "youtu.be" = listHead pathParts
        | host `elem` ["youtube.com", "www.youtube.com", "m.youtube.com"] = youtubeComId pathParts (Text.pack (uriQuery uri))
        | otherwise = Nothing
  candidate >>= validVideoId

youtubeComId :: [Text] -> Text -> Maybe Text
youtubeComId pathParts query = case pathParts of
  ["watch"] -> lookupQuery "v" query
  kind : identifier : _ | kind `elem` ["shorts", "embed"] -> Just identifier
  _ -> Nothing

lookupQuery :: Text -> Text -> Maybe Text
lookupQuery key query =
  let pairs = map (Text.breakOn "=") (Text.splitOn "&" (Text.dropWhile (== '?') query))
   in snd <$> listHead (filter ((== key) . fst) pairs) >>= nonEmpty . Text.drop 1

validVideoId :: Text -> Maybe Text
validVideoId identifier
  | Text.length identifier == 11 && Text.all valid identifier = Just identifier
  | otherwise = Nothing
  where
    valid character = character == '-' || character == '_' || ('0' <= character && character <= '9') || ('A' <= character && character <= 'Z') || ('a' <= character && character <= 'z')

pdfRectangle :: Object -> PdfAction (Rect PdfSpace)
pdfRectangle object = case arrayValue object >>= fourNumbers of
  Nothing -> throwError (PdfStructureError "annotation Rect must contain four numbers")
  Just [x1, y1, x2, y2] -> pure (Rect (Coordinate (min x1 x2)) (Coordinate (min y1 y2)) (Coordinate (abs (x2 - x1))) (Coordinate (abs (y2 - y1))))
  Just _ -> throwError (PdfStructureError "annotation Rect must contain four numbers")

fourNumbers :: Array -> Maybe [Double]
fourNumbers values
  | Vector.length values == 4 = traverse realValue (Vector.toList values)
  | otherwise = Nothing

requireResolvedDict :: Pdf -> Dict -> Name -> PdfAction Dict
requireResolvedDict pdf dictionary key = requireKey dictionary key >>= resolvedDict pdf <*> pure (nameText key)

optionalResolvedDict :: Pdf -> Dict -> Name -> PdfAction Dict
optionalResolvedDict pdf dictionary key = case HashMap.lookup key dictionary of
  Nothing -> pure HashMap.empty
  Just object -> resolvedDict pdf object (nameText key)

resolvedDict :: Pdf -> Object -> Text -> PdfAction Dict
resolvedDict pdf object label = resolve pdf object >>= requireDict label

requireDict :: Text -> Object -> PdfAction Dict
requireDict label object = maybe (throwError (PdfStructureError (label <> " is not a dictionary"))) pure (dictValue object)

requireArray :: Text -> Object -> PdfAction Array
requireArray label object = maybe (throwError (PdfStructureError (label <> " is not an array"))) pure (arrayValue object)

requireKey :: Dict -> Name -> PdfAction Object
requireKey dictionary key = maybe (throwError (PdfStructureError ("missing PDF key /" <> nameText key))) pure (HashMap.lookup key dictionary)

requireInt :: Dict -> Name -> PdfAction Int
requireInt dictionary key = requireKey dictionary key >>= maybe (throwError (PdfStructureError (nameText key <> " is not an integer"))) pure . intValue

requireName :: Dict -> Name -> PdfAction Name
requireName dictionary key = requireKey dictionary key >>= maybe (throwError (PdfStructureError (nameText key <> " is not a name"))) pure . nameValue

resolve :: Pdf -> Object -> PdfAction Object
resolve pdf = go Set.empty
  where
    go :: Set Ref -> Object -> PdfAction Object
    go seen (Ref reference)
      | Set.member reference seen = throwError (PdfStructureError "cyclic indirect object reference")
      | otherwise = liftIO (lookupObject pdf reference) >>= go (Set.insert reference seen)
    go _ object = pure object

resolveWithReference :: Pdf -> Object -> PdfAction (Maybe (Ref, Object))
resolveWithReference pdf (Ref reference) = Just . (reference,) <$> liftIO (lookupObject pdf reference)
resolveWithReference _ _ = pure Nothing

readDecodedStream :: Pdf -> Ref -> Stream -> PdfAction ByteString
readDecodedStream pdf reference stream = liftIO (streamContent pdf reference stream >>= readAll)

readRawStream :: Pdf -> Ref -> Stream -> PdfAction ByteString
readRawStream pdf reference stream = liftIO (rawStreamContent pdf reference stream >>= readAll)

readAll :: Streams.InputStream ByteString -> IO ByteString
readAll input = ByteString.concat <$> Streams.toList input

nameText :: Name -> Text
nameText = Text.decodeLatin1 . toByteString

listHead :: [a] -> Maybe a
listHead [] = Nothing
listHead (value : _) = Just value

nonEmpty :: Text -> Maybe Text
nonEmpty value
  | Text.null value = Nothing
  | otherwise = Just value
