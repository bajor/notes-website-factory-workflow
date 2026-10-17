{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The effectful boundary around SVG source documents.
--
-- The generated site shows the source SVG unchanged, as an isolated image
-- embedded in the scene. Browsers draw such an image without scripts, links,
-- or external files and drop that content without reporting an error. This
-- module therefore rejects the forms of that content it can recognize.
module Factory.Svg
  ( SvgBoard (..)
  , ValidatedSvg (..)
  , interpretSvg
  , readSvg
  , svgScene
  ) where

import Control.Exception (IOException, displayException, try)
import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.Char (toLower)
import Data.Foldable (traverse_)
import Data.Text (Text)
import Factory.Domain
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LazyByteString
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Text.Read as Text
import qualified Text.XML as Xml

-- | The board measured in CSS pixels, the SVG user unit of an untransformed root.
data SvgBoard = SvgBoard
  { svgBoardWidth :: Coordinate BoardSpace
  , svgBoardHeight :: Coordinate BoardSpace
  }
  deriving stock (Eq, Show)

-- | A source that passed validation, with the exact bytes the site embeds.
data ValidatedSvg = ValidatedSvg
  { validatedBoard :: SvgBoard
  , validatedBytes :: ByteString.ByteString
  }

-- | A root size attribute; percentages give no size, as for an image in a browser.
data RootLength = AbsoluteLength Double | NoLength

svgNamespace, xlinkNamespace, xhtmlNamespace :: Text
svgNamespace = "http://www.w3.org/2000/svg"
xlinkNamespace = "http://www.w3.org/1999/xlink"
xhtmlNamespace = "http://www.w3.org/1999/xhtml"

readSvg :: FilePath -> IO (Either BuildError ValidatedSvg)
readSvg path = do
  source <- try (ByteString.readFile path)
  pure $ case source of
    Left exception -> Left (IoError (Text.pack (displayException (exception :: IOException))))
    Right bytes -> (`ValidatedSvg` bytes) <$> interpretSvg (LazyByteString.fromStrict bytes)

-- | Embed the exact source bytes as a data URI. No standalone SVG file is
-- published, so a browser can never open the source as a document that runs
-- content the validator did not recognize.
svgScene :: ValidatedSvg -> Scene 'Unvalidated
svgScene (ValidatedSvg (SvgBoard width height) bytes) =
  Scene width height [] [SvgDocumentNode ("data:image/svg+xml;base64," <> Text.decodeLatin1 (Base64.encode bytes)) (Rect 0 0 width height)]

interpretSvg :: LazyByteString.ByteString -> Either BuildError SvgBoard
interpretSvg bytes = do
  document <- first (InvalidSvg . Text.pack . displayException) (Xml.parseLBS Xml.def bytes)
  let root = Xml.documentRoot document
      elements = descendants root
  -- xml-conduit keeps an entity reference in a namespace declaration as literal
  -- text, while browsers expand it, so such names would be misread.
  when (any usesEntityNamespace elements) (Left (InvalidSvg "namespace declarations must not use entity references"))
  unless (Xml.elementName root == svgName "svg") (Left (InvalidSvg "the root element must be svg in the SVG namespace"))
  board <- rootBoard root
  traverse_ checkInstruction (documentInstructions document)
  traverse_ checkElement elements
  pure board

svgName :: Text -> Xml.Name
svgName localName = Xml.Name localName (Just svgNamespace) Nothing

rootBoard :: Xml.Element -> Either BuildError SvgBoard
rootBoard root = do
  width <- rootLength "width" root
  height <- rootLength "height" root
  case (width, height) of
    (AbsoluteLength w, AbsoluteLength h) -> positiveBoard w h
    (NoLength, NoLength) -> viewBoxSize root >>= uncurry positiveBoard
    _ -> Left (InvalidSvg "width and height must both be absolute lengths, or neither")

positiveBoard :: Double -> Double -> Either BuildError SvgBoard
positiveBoard width height
  | all positiveFinite [width, height] = Right (SvgBoard (Coordinate width) (Coordinate height))
  | otherwise = Left (InvalidSvg "the board width and height must be finite and positive")
  where
    positiveFinite value = not (isNaN value || isInfinite value) && value > 0

rootLength :: Text -> Xml.Element -> Either BuildError RootLength
rootLength name root = case Map.lookup (Xml.Name name Nothing Nothing) (Xml.elementAttributes root) of
  Nothing -> Right NoLength
  Just raw -> case svgNumber (Text.strip raw) of
    Right (value, unit)
      | unit == "%" -> Right NoLength
      | Just pixels <- lookup (Text.map toLower unit) cssPixelsPerUnit -> Right (AbsoluteLength (value * pixels))
    _ -> Left (InvalidSvg (name <> " must be an absolute length or a percentage: " <> raw))

-- | Absolute CSS units, with 96 CSS pixels per inch.
cssPixelsPerUnit :: [(Text, Double)]
cssPixelsPerUnit = [("", 1), ("px", 1), ("pt", 96 / 72), ("pc", 16), ("in", 96), ("cm", 96 / 2.54), ("mm", 96 / 25.4)]

viewBoxSize :: Xml.Element -> Either BuildError (Double, Double)
viewBoxSize root = case Map.lookup (Xml.Name "viewBox" Nothing Nothing) (Xml.elementAttributes root) of
  Nothing -> Left (InvalidSvg "an SVG without an absolute width and height needs a viewBox")
  Just raw -> case traverse svgNumber (filter (not . Text.null) (Text.split (`elem` [',', ' ', '\t', '\n', '\r']) raw)) of
    Right [(_, ""), (_, ""), (width, ""), (height, "")] -> Right (width, height)
    _ -> Left (InvalidSvg ("viewBox must contain four numbers: " <> raw))

-- | Read a leading SVG number, which may omit the digit before its point, and return the remaining text.
svgNumber :: Text -> Either String (Double, Text)
svgNumber text = Text.signed Text.double $ case Text.uncons text of
  Just (sign, rest) | sign `elem` ['-', '+'] -> Text.cons sign (withLeadingDigit rest)
  _ -> withLeadingDigit text
  where
    withLeadingDigit value = if "." `Text.isPrefixOf` value then "0" <> value else value

documentInstructions :: Xml.Document -> [Xml.Instruction]
documentInstructions document =
  [instruction | Xml.MiscInstruction instruction <- before <> after <> Xml.documentEpilogue document]
  where
    Xml.Prologue before _ after = Xml.documentPrologue document

checkInstruction :: Xml.Instruction -> Either BuildError ()
checkInstruction instruction =
  when (Xml.instructionTarget instruction == "xml-stylesheet") (unsupported "external SVG stylesheets are not supported")

descendants :: Xml.Element -> [Xml.Element]
descendants element = element : concat [descendants child | Xml.NodeElement child <- Xml.elementNodes element]

usesEntityNamespace :: Xml.Element -> Bool
usesEntityNamespace element =
  any (maybe False ("&" `Text.isInfixOf`) . Xml.nameNamespace) (Xml.elementName element : Map.keys (Xml.elementAttributes element))

-- | Element names are matched in every namespace, and XHTML elements are
-- rejected outright, because browsers act on XHTML content inside SVG.
checkElement :: Xml.Element -> Either BuildError ()
checkElement element = do
  when (Xml.nameNamespace (Xml.elementName element) == Just xhtmlNamespace) (unsupported "SVG content in the XHTML namespace is not supported")
  traverse_ unsupported (lookup localName unsupportedElements)
  traverse_ (checkAttribute localName) (Map.toList (Xml.elementAttributes element))
  -- Browsers join a style element's text nodes before parsing the stylesheet.
  when (localName == "style") (checkStylesheet (Text.concat [css | Xml.NodeContent css <- children]))
  traverse_ checkInstruction [instruction | Xml.NodeInstruction instruction <- children]
  where
    localName = Xml.nameLocalName (Xml.elementName element)
    children = Xml.elementNodes element

unsupportedElements :: [(Text, Text)]
unsupportedElements =
  [ ("script", "SVG scripts are not supported")
  , ("a", "SVG hyperlinks are not supported")
  , ("foreignObject", "SVG foreignObject content is not supported")
  ]

checkAttribute :: Text -> (Xml.Name, Text) -> Either BuildError ()
checkAttribute elementName (name, value)
  | Xml.nameNamespace name == Nothing && "on" `Text.isPrefixOf` Text.map toLower (Xml.nameLocalName name) =
      unsupported "SVG event handler attributes are not supported"
  | isHref && elementName `elem` ["image", "feImage"] = checkReference value
  | isHref = checkElementReference elementName value
  | otherwise = traverse_ checkReference (cssUrlTargets value)
  where
    isHref = Xml.nameLocalName name == "href" && Xml.nameNamespace name `elem` [Nothing, Just xlinkNamespace]

checkStylesheet :: Text -> Either BuildError ()
checkStylesheet css = do
  when ("@import" `Text.isInfixOf` Text.map toLower css) (unsupported "SVG stylesheets must not import other stylesheets")
  traverse_ checkReference (cssUrlTargets css)

-- | Only same-document fragments and data URIs load inside an isolated SVG image.
checkReference :: Text -> Either BuildError ()
checkReference reference
  | "#" `Text.isPrefixOf` target || "data:" `Text.isPrefixOf` Text.map toLower target = Right ()
  | otherwise = unsupported ("SVG references an external resource: " <> target)
  where
    target = Text.strip reference

-- | Only image elements load a data URI; other references name an element,
-- and browsers draw nothing for one that targets a data URI.
checkElementReference :: Text -> Text -> Either BuildError ()
checkElementReference elementName reference
  | "#" `Text.isPrefixOf` Text.strip reference = Right ()
  | otherwise = unsupported ("SVG " <> elementName <> " elements must reference an element in the same file")

-- | The targets of every CSS @url(...)@ in a value, without quotes.
--
-- Mapping 'toLower' over characters, unlike 'Text.toLower', keeps offsets valid.
cssUrlTargets :: Text -> [Text]
cssUrlTargets css =
  [ Text.takeWhile (`notElem` [')', '"', '\'']) (Text.dropWhile (`elem` [' ', '\t', '\n', '\r', '"', '\'']) (Text.drop (Text.length before + Text.length opening) css))
  | (before, _) <- Text.breakOnAll opening (Text.map toLower css)
  ]
  where
    opening = "url("

unsupported :: Text -> Either BuildError a
unsupported = Left . UnsupportedSvg
