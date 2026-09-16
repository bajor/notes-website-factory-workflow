{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The vocabulary shared by every factory stage.
--
-- A parser becomes difficult to understand when every number is just a
-- 'Double' and every string is just 'Text'. These small types name the facts
-- in our domain. They also prevent code from accidentally treating a PDF
-- coordinate as a board coordinate.
module Factory.Domain
  ( Asset (..)
  , AssetId (..)
  , BoardSpace
  , BuildError (..)
  , ClipPath (..)
  , ClipRule (..)
  , Color (..)
  , Coordinate (..)
  , DeviceColorSpace (..)
  , FillRule (..)
  , GameUrl (..)
  , LinkTarget (..)
  , Matrix (..)
  , PaintStyle (..)
  , PathCommand (..)
  , PdfSpace
  , Point (..)
  , Rect (..)
  , Scene (..)
  , SceneNode (..)
  , SiteTitle
  , TextRun (..)
  , Validation (..)
  , VectorPath (..)
  , VectorShape (..)
  , VideoId (..)
  , WebUrl (..)
  , mkSiteTitle
  , sceneNodes
  , siteTitleText
  ) where

import Data.Aeson (ToJSON (toJSON), object, (.=))
import Data.Char (isControl)
import Data.Text (Text)
import qualified Data.Text as Text

-- | A type-level label saying whether validation has run.
data Validation = Unvalidated | Validated

-- | Empty marker types used only by the compiler.
data PdfSpace
data BoardSpace

newtype Coordinate space = Coordinate {unCoordinate :: Double}
  deriving stock (Eq, Show)
  deriving newtype (Num)

data Point space = Point
  { pointX :: Coordinate space
  , pointY :: Coordinate space
  }
  deriving stock (Eq, Show)

data Rect space = Rect
  { rectX :: Coordinate space
  , rectY :: Coordinate space
  , rectWidth :: Coordinate space
  , rectHeight :: Coordinate space
  }
  deriving stock (Eq, Show)

-- | PDF and CSS both use six numbers for a two-dimensional affine matrix.
data Matrix = Matrix
  { matrixA :: Double
  , matrixB :: Double
  , matrixC :: Double
  , matrixD :: Double
  , matrixE :: Double
  , matrixF :: Double
  }
  deriving stock (Eq, Show)

data PathCommand
  = MoveTo (Point BoardSpace)
  | LineTo (Point BoardSpace)
  | CurveTo (Point BoardSpace) (Point BoardSpace) (Point BoardSpace)
  | ClosePath
  deriving stock (Eq, Show)

data FillRule = NonZero | EvenOdd
  deriving stock (Eq, Show)

data ClipRule = ClipNonZero | ClipEvenOdd
  deriving stock (Eq, Show)

data ClipPath = ClipPath
  { clipRule :: ClipRule
  , clipCommands :: [PathCommand]
  }
  deriving stock (Eq, Show)

data Color = Color
  { colorRed :: Double
  , colorGreen :: Double
  , colorBlue :: Double
  }
  deriving stock (Eq, Show)

data DeviceColorSpace = GrayColorSpace | RgbColorSpace | CmykColorSpace
  deriving stock (Eq, Show)

data PaintStyle = PaintStyle
  { paintFill :: Maybe (Color, FillRule)
  , paintStroke :: Maybe Color
  , paintLineWidth :: Double
  , paintMiterLimit :: Double
  , paintDashArray :: [Double]
  , paintDashPhase :: Double
  , paintOpacity :: Double
  }
  deriving stock (Eq, Show)

newtype AssetId = AssetId {unAssetId :: Text}
  deriving stock (Eq, Ord, Show)

data Asset = Asset
  { assetId :: AssetId
  , assetFile :: FilePath
  , assetWidth :: Int
  , assetHeight :: Int
  }
  deriving stock (Eq, Show)

newtype VideoId = VideoId {unVideoId :: Text}
  deriving stock (Eq, Show)

newtype GameUrl = GameUrl {unGameUrl :: Text}
  deriving stock (Eq, Show)

newtype WebUrl = WebUrl {unWebUrl :: Text}
  deriving stock (Eq, Show)

newtype SiteTitle = SiteTitle Text
  deriving stock (Eq, Show)

mkSiteTitle :: Text -> Either BuildError SiteTitle
mkSiteTitle rawTitle
  | Text.null title = Left (InvalidSiteTitle "site title must not be empty")
  | Text.any isControl title = Left (InvalidSiteTitle "site title must not contain control characters")
  | otherwise = Right (SiteTitle title)
  where
    title = Text.strip rawTitle

siteTitleText :: SiteTitle -> Text
siteTitleText (SiteTitle title) = title

data LinkTarget = YouTube VideoId | Game GameUrl | External WebUrl
  deriving stock (Eq, Show)

data TextRun = TextRun
  { textValue :: Text
  , textFontFamily :: Text
  , textFontSize :: Double
  , textMatrix :: Matrix
  , textOpacity :: Double
  }
  deriving stock (Eq, Show)

newtype VectorPath = VectorPath {unVectorPath :: Text}
  deriving stock (Eq, Show)

data VectorShape = VectorShape
  { vectorPath :: VectorPath
  , vectorColor :: Color
  , vectorOpacity :: Double
  }
  deriving stock (Eq, Show)

data SceneNode
  = ImageNode AssetId Matrix Double [ClipPath]
  | VectorArtworkNode [VectorShape] Matrix Double [ClipPath]
  | PathNode [PathCommand] PaintStyle [ClipPath]
  | TextNode TextRun [ClipPath]
  | LinkNode LinkTarget (Rect BoardSpace)
  deriving stock (Eq, Show)

-- | The phase parameter makes unvalidated scenes unusable by the emitter.
data Scene (phase :: Validation) = Scene
  { sceneWidth :: Coordinate BoardSpace
  , sceneHeight :: Coordinate BoardSpace
  , sceneAssets :: [Asset]
  , sceneContent :: [SceneNode]
  }
  deriving stock (Eq, Show)

sceneNodes :: Scene phase -> [SceneNode]
sceneNodes = sceneContent

data BuildError
  = PdfCountError Int
  | PageCountError Int
  | PdfStructureError Text
  | UnsupportedOperator Text
  | UnsupportedImage Text
  | GraphicsStateError Text
  | InvalidScene Text
  | InvalidUrl Text
  | InvalidSiteTitle Text
  | EvaluationError Text
  | IoError Text
  deriving stock (Eq, Show)

instance ToJSON Matrix where
  toJSON matrix =
    object
      [ "a" .= matrixA matrix
      , "b" .= matrixB matrix
      , "c" .= matrixC matrix
      , "d" .= matrixD matrix
      , "e" .= matrixE matrix
      , "f" .= matrixF matrix
      ]

instance ToJSON (Point BoardSpace) where
  toJSON (Point x y) = object ["x" .= unCoordinate x, "y" .= unCoordinate y]

instance ToJSON (Rect BoardSpace) where
  toJSON rectangle =
    object
      [ "x" .= unCoordinate (rectX rectangle)
      , "y" .= unCoordinate (rectY rectangle)
      , "width" .= unCoordinate (rectWidth rectangle)
      , "height" .= unCoordinate (rectHeight rectangle)
      ]

instance ToJSON PathCommand where
  toJSON command = case command of
    MoveTo point -> object ["kind" .= ("move" :: Text), "point" .= point]
    LineTo point -> object ["kind" .= ("line" :: Text), "point" .= point]
    CurveTo first second end ->
      object
        [ "kind" .= ("curve" :: Text)
        , "first" .= first
        , "second" .= second
        , "end" .= end
        ]
    ClosePath -> object ["kind" .= ("close" :: Text)]

instance ToJSON ClipPath where
  toJSON clip =
    object
      [ "rule" .= case clipRule clip of ClipNonZero -> ("nonzero" :: Text); ClipEvenOdd -> "evenodd"
      , "commands" .= clipCommands clip
      ]

instance ToJSON Color where
  toJSON color = object ["r" .= colorRed color, "g" .= colorGreen color, "b" .= colorBlue color]

instance ToJSON PaintStyle where
  toJSON style =
    object
      [ "fill" .= fmap encodeFill (paintFill style)
      , "stroke" .= paintStroke style
      , "lineWidth" .= paintLineWidth style
      , "miterLimit" .= paintMiterLimit style
      , "dashArray" .= paintDashArray style
      , "dashPhase" .= paintDashPhase style
      , "opacity" .= paintOpacity style
      ]
    where
      encodeFill (color, rule) =
        object
          [ "color" .= color
          , "rule" .= case rule of NonZero -> ("nonzero" :: Text); EvenOdd -> "evenodd"
          ]

instance ToJSON VectorShape where
  toJSON shape =
    object
      [ "path" .= unVectorPath (vectorPath shape)
      , "color" .= vectorColor shape
      , "opacity" .= vectorOpacity shape
      ]

instance ToJSON SceneNode where
  toJSON node = case node of
    ImageNode identifier matrix opacity clips ->
      object
        [ "kind" .= ("image" :: Text)
        , "asset" .= unAssetId identifier
        , "matrix" .= matrix
        , "opacity" .= opacity
        , "clips" .= clips
        ]
    VectorArtworkNode shapes matrix opacity clips ->
      object
        [ "kind" .= ("vector-artwork" :: Text)
        , "shapes" .= shapes
        , "matrix" .= matrix
        , "opacity" .= opacity
        , "clips" .= clips
        ]
    PathNode commands style clips ->
      object
        [ "kind" .= ("path" :: Text)
        , "commands" .= commands
        , "style" .= style
        , "clips" .= clips
        ]
    TextNode run clips ->
      object
        [ "kind" .= ("text" :: Text)
        , "value" .= textValue run
        , "fontFamily" .= textFontFamily run
        , "fontSize" .= textFontSize run
        , "matrix" .= textMatrix run
        , "opacity" .= textOpacity run
        , "clips" .= clips
        ]
    LinkNode target bounds ->
      object
        [ "kind" .= ("link" :: Text)
        , "target" .= encodeTarget target
        , "bounds" .= bounds
        ]
    where
      encodeTarget target = case target of
        YouTube videoId -> object ["kind" .= ("youtube" :: Text), "videoId" .= unVideoId videoId]
        Game url -> object ["kind" .= ("game" :: Text), "url" .= unGameUrl url]
        External url -> object ["kind" .= ("external" :: Text), "url" .= unWebUrl url]

instance ToJSON Asset where
  toJSON asset =
    object
      [ "id" .= unAssetId (assetId asset)
      , "file" .= assetFile asset
      , "width" .= assetWidth asset
      , "height" .= assetHeight asset
      ]

instance ToJSON (Scene 'Validated) where
  toJSON scene =
    object
      [ "width" .= unCoordinate (sceneWidth scene)
      , "height" .= unCoordinate (sceneHeight scene)
      , "assets" .= sceneAssets scene
       , "nodes" .= sceneContent scene
      ]
