{-# LANGUAGE OverloadedStrings #-}

-- | Interpret PDF drawing operators as immutable scene nodes.
--
-- This module demonstrates a functional state machine. 'foldM' visits one
-- operator at a time. Each visit receives the old state and returns a new
-- state. Nothing is changed in place, which makes every transition testable.
module Factory.Interpreter
  ( ColorSpaceResource (..)
  , Resources (..)
  , VisualResource (..)
  , interpretOperators
  ) where

import Control.Monad (foldM)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Factory.Domain
import Factory.Geometry
import Pdf.Content (Op (..), Operator)
import Pdf.Core (Name, Object)
import Pdf.Core.Name (toByteString)
import Pdf.Core.Object.Util (arrayValue, nameValue, realValue)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Vector as Vector

data Resources = Resources
  { resourceImages :: Map Name VisualResource
  , resourceAlpha :: Map Name Double
  , resourceColorSpaces :: Map Name ColorSpaceResource
  }
  deriving stock (Eq, Show)

data ColorSpaceResource
  = SupportedColorSpace DeviceColorSpace
  | UnsupportedColorSpace
  deriving stock (Eq, Show)

data VisualResource
  = RasterResource AssetId
  | VectorResource [VectorShape]
  | MixedResource [VectorShape] AssetId
  deriving stock (Eq, Show)

data GraphicsState = GraphicsState
  { currentMatrix :: Matrix
  , currentClips :: [ClipPath]
  , currentOpacity :: Double
  , currentFill :: Color
  , currentStroke :: Color
  , currentFillColorSpace :: DeviceColorSpace
  , currentStrokeColorSpace :: DeviceColorSpace
  , currentLineWidth :: Double
  , currentMiterLimit :: Double
  , currentDashArray :: [Double]
  , currentDashPhase :: Double
  }
  deriving stock (Eq, Show)

data Machine = Machine
  { machineGraphics :: GraphicsState
  , machineStack :: [GraphicsState]
  , machinePath :: [PathCommand]
  , machinePendingClip :: Maybe ClipRule
  , machineNodes :: [SceneNode]
  }
  deriving stock (Eq, Show)

initialGraphics :: GraphicsState
initialGraphics =
  GraphicsState
    { currentMatrix = identityMatrix
    , currentClips = []
    , currentOpacity = 1
    , currentFill = Color 0 0 0
    , currentStroke = Color 0 0 0
    , currentFillColorSpace = GrayColorSpace
    , currentStrokeColorSpace = GrayColorSpace
    , currentLineWidth = 1
    , currentMiterLimit = 10
    , currentDashArray = []
    , currentDashPhase = 0
    }

initialMachine :: Machine
initialMachine = Machine initialGraphics [] [] Nothing []

interpretOperators :: Coordinate PdfSpace -> Resources -> [Operator] -> Either BuildError [SceneNode]
interpretOperators pageHeight resources operators = do
  final <- foldM (step pageHeight resources) initialMachine operators
  if null (machineStack final)
    then Right (reverse (machineNodes final))
    else Left (GraphicsStateError "content stream ended before every q had a matching Q")

step :: Coordinate PdfSpace -> Resources -> Machine -> Operator -> Either BuildError Machine
step pageHeight resources machine operator = case operator of
  (Op_q, []) -> Right machine {machineStack = machineGraphics machine : machineStack machine}
  (Op_Q, []) -> restoreGraphics machine
  (Op_cm, values) -> do
    matrix <- matrixFrom values
    let graphics = machineGraphics machine
    Right machine {machineGraphics = graphics {currentMatrix = multiplyMatrix matrix (currentMatrix graphics)}}
  (Op_gs, [value]) -> setAlpha resources machine value
  (Op_w, [value]) -> setLineWidth machine value
  (Op_M, [value]) -> setMiterLimit machine value
  (Op_d, [values, phase]) -> setDashPattern machine values phase
  (Op_CS, [value]) -> selectColorSpace resources False machine value
  (Op_cs, [value]) -> selectColorSpace resources True machine value
  (Op_SC, values) -> setSelectedColor False machine values
  (Op_sc, values) -> setSelectedColor True machine values
  (Op_g, [value]) -> setGray True machine value
  (Op_G, [value]) -> setGray False machine value
  (Op_rg, values) -> setRgb True machine values
  (Op_RG, values) -> setRgb False machine values
  (Op_k, values) -> setCmyk True machine values
  (Op_K, values) -> setCmyk False machine values
  (Op_m, values) -> appendPoint pageHeight machine MoveTo values
  (Op_l, values) -> appendPoint pageHeight machine LineTo values
  (Op_c, values) -> appendCurve pageHeight machine values
  (Op_v, values) -> appendShorthandCurve pageHeight True machine values
  (Op_y, values) -> appendShorthandCurve pageHeight False machine values
  (Op_h, []) -> Right machine {machinePath = machinePath machine <> [ClosePath]}
  (Op_re, values) -> appendRectangle pageHeight machine values
  (Op_W, []) -> Right machine {machinePendingClip = Just ClipNonZero}
  (Op_W_star, []) -> Right machine {machinePendingClip = Just ClipEvenOdd}
  (Op_n, []) -> Right (finishWithoutPaint machine)
  (Op_S, []) -> finishWithPaint machine Nothing True NonZero
  (Op_s, []) -> finishWithPaint (closeCurrentPath machine) Nothing True NonZero
  (Op_f, []) -> finishWithPaint machine (Just (currentFill (machineGraphics machine))) False NonZero
  (Op_F, []) -> finishWithPaint machine (Just (currentFill (machineGraphics machine))) False NonZero
  (Op_f_star, []) -> finishWithPaint machine (Just (currentFill (machineGraphics machine))) False EvenOdd
  (Op_B, []) -> finishWithPaint machine (Just (currentFill (machineGraphics machine))) True NonZero
  (Op_B_star, []) -> finishWithPaint machine (Just (currentFill (machineGraphics machine))) True EvenOdd
  (Op_b, []) -> finishWithPaint (closeCurrentPath machine) (Just (currentFill (machineGraphics machine))) True NonZero
  (Op_b_star, []) -> finishWithPaint (closeCurrentPath machine) (Just (currentFill (machineGraphics machine))) True EvenOdd
  (Op_Do, [value]) -> emitImage pageHeight resources machine value
  (Op_BT, []) -> Left (UnsupportedOperator "PDF text requires font decoding and metrics")
  (Op_ri, _) -> Right machine
  (Op_BMC, _) -> Right machine
  (Op_BDC, _) -> Right machine
  (Op_EMC, _) -> Right machine
  _ -> Left (UnsupportedOperator (Text.pack (show operator)))

restoreGraphics :: Machine -> Either BuildError Machine
restoreGraphics machine = case machineStack machine of
  [] -> Left (GraphicsStateError "Q tried to restore an empty graphics-state stack")
  previous : rest -> Right machine {machineGraphics = previous, machineStack = rest}

matrixFrom :: [Object] -> Either BuildError Matrix
matrixFrom values = case traverse number values of
  Right [a, b, c, d, e, f] -> Right (Matrix a b c d e f)
  _ -> Left (PdfStructureError "matrix operator expected six numbers")

number :: Object -> Either BuildError Double
number value = maybe (Left (PdfStructureError "operator expected a number")) Right (realValue value)

pointFrom :: Coordinate PdfSpace -> Matrix -> [Object] -> Either BuildError (Point BoardSpace)
pointFrom height matrix values = case traverse number values of
  Right [x, y] -> Right (pdfPointToBoard height (applyMatrix matrix (Point (Coordinate x) (Coordinate y))))
  _ -> Left (PdfStructureError "path operator expected two numbers")

appendPoint :: Coordinate PdfSpace -> Machine -> (Point BoardSpace -> PathCommand) -> [Object] -> Either BuildError Machine
appendPoint pageHeight machine constructor values = do
  point <- pointFrom pageHeight (currentMatrix (machineGraphics machine)) values
  Right machine {machinePath = machinePath machine <> [constructor point]}
appendCurve :: Coordinate PdfSpace -> Machine -> [Object] -> Either BuildError Machine
appendCurve height machine values = case chunksOfTwo values of
  [first, second, end] -> do
    firstPoint <- pointFrom height matrix first
    secondPoint <- pointFrom height matrix second
    endPoint <- pointFrom height matrix end
    Right machine {machinePath = machinePath machine <> [CurveTo firstPoint secondPoint endPoint]}
  _ -> Left (PdfStructureError "curve operator expected six numbers")
  where
    matrix = currentMatrix (machineGraphics machine)

appendShorthandCurve :: Coordinate PdfSpace -> Bool -> Machine -> [Object] -> Either BuildError Machine
appendShorthandCurve height firstIsCurrent machine values = case chunksOfTwo values of
  [first, end] -> do
    firstPoint <- pointFrom height matrix first
    endPoint <- pointFrom height matrix end
    let current = currentPathPoint machine
        command = if firstIsCurrent then CurveTo current firstPoint endPoint else CurveTo firstPoint endPoint endPoint
    Right machine {machinePath = machinePath machine <> [command]}
  _ -> Left (PdfStructureError "shorthand curve operator expected four numbers")
  where
    matrix = currentMatrix (machineGraphics machine)

appendRectangle :: Coordinate PdfSpace -> Machine -> [Object] -> Either BuildError Machine
appendRectangle height machine values = case traverse number values of
  Right [x, y, width, rectangleHeight] ->
    let matrix = currentMatrix (machineGraphics machine)
        transformPoint px py = pdfPointToBoard height (applyMatrix matrix (Point (Coordinate px) (Coordinate py)))
        commands =
          [ MoveTo (transformPoint x y)
          , LineTo (transformPoint (x + width) y)
          , LineTo (transformPoint (x + width) (y + rectangleHeight))
          , LineTo (transformPoint x (y + rectangleHeight))
          , ClosePath
          ]
     in Right machine {machinePath = machinePath machine <> commands}
  _ -> Left (PdfStructureError "rectangle operator expected four numbers")

finishWithoutPaint :: Machine -> Machine
finishWithoutPaint = clearPath . applyPendingClip

finishWithPaint :: Machine -> Maybe Color -> Bool -> FillRule -> Either BuildError Machine
finishWithPaint machine fillColor hasStroke fillRule = do
  strokeScale <-
    if hasStroke && not (null (machinePath machine))
      then similarityScale (currentMatrix graphics)
      else Right 1
  Right (clearPath (appendNode (applyPendingClip machine) strokeScale))
  where
    graphics = machineGraphics machine
    style strokeScale =
      PaintStyle
        { paintFill = fmap (,fillRule) fillColor
        , paintStroke = if hasStroke then Just (currentStroke graphics) else Nothing
        , paintLineWidth = strokeScale * currentLineWidth graphics
        , paintMiterLimit = currentMiterLimit graphics
        , paintDashArray = map (strokeScale *) (currentDashArray graphics)
        , paintDashPhase = strokeScale * currentDashPhase graphics
        , paintOpacity = currentOpacity graphics
        }
    appendNode current strokeScale
      | null (machinePath machine) = current
      | otherwise = current {machineNodes = PathNode (machinePath machine) (style strokeScale) (currentClips graphics) : machineNodes current}

similarityScale :: Matrix -> Either BuildError Double
similarityScale (Matrix a b c d _ _) =
  if determinant /= 0 && sameLength && orthogonal
    then Right scale
    else Left (UnsupportedOperator "stroked paths require a non-singular similarity transform")
  where
    firstSquared = a * a + b * b
    secondSquared = c * c + d * d
    dotProduct = a * c + b * d
    determinant = a * d - b * c
    scale = sqrt firstSquared
    sameLength = abs (firstSquared - secondSquared) <= similarityTolerance * max firstSquared secondSquared
    orthogonal = abs dotProduct <= similarityTolerance * sqrt (firstSquared * secondSquared)

similarityTolerance :: Double
similarityTolerance = 1e-9

applyPendingClip :: Machine -> Machine
applyPendingClip machine = case machinePendingClip machine of
  Nothing -> machine
  Just rule ->
    let graphics = machineGraphics machine
        clip = ClipPath rule (machinePath machine)
     in machine {machineGraphics = graphics {currentClips = currentClips graphics <> [clip]}, machinePendingClip = Nothing}

clearPath :: Machine -> Machine
clearPath machine = machine {machinePath = [], machinePendingClip = Nothing}

closeCurrentPath :: Machine -> Machine
closeCurrentPath machine = machine {machinePath = machinePath machine <> [ClosePath]}

currentPathPoint :: Machine -> Point BoardSpace
currentPathPoint machine = case reverse (machinePath machine) of
  ClosePath : previous -> subpathStart previous
  MoveTo point : _ -> point
  LineTo point : _ -> point
  CurveTo _ _ point : _ -> point
  _ -> Point 0 0
  where
    subpathStart commands = case dropWhile (not . isMove) commands of
      MoveTo point : _ -> point
      _ -> Point 0 0
    isMove MoveTo {} = True
    isMove _ = False

emitImage :: Coordinate PdfSpace -> Resources -> Machine -> Object -> Either BuildError Machine
emitImage height resources machine value = do
  name <- maybe (Left (PdfStructureError "Do expected an image resource name")) Right (nameValue value)
  resource <- maybe (Left (PdfStructureError ("missing image resource " <> nameText name))) Right (Map.lookup name (resourceImages resources))
  let graphics = machineGraphics machine
      matrix = boardMatrix height (currentMatrix graphics)
      opacity = currentOpacity graphics
      clips = currentClips graphics
      nodes = case resource of
        RasterResource identifier -> [ImageNode identifier matrix opacity clips]
        VectorResource shapes -> [VectorArtworkNode shapes matrix opacity clips]
        MixedResource shapes identifier -> [VectorArtworkNode shapes matrix opacity clips, ImageNode identifier matrix opacity clips]
  Right machine {machineNodes = reverse nodes <> machineNodes machine}

setAlpha :: Resources -> Machine -> Object -> Either BuildError Machine
setAlpha resources machine value = do
  name <- maybe (Left (PdfStructureError "gs expected a graphics-state name")) Right (nameValue value)
  opacity <- maybe (Left (PdfStructureError ("missing ExtGState resource " <> nameText name))) Right (Map.lookup name (resourceAlpha resources))
  let graphics = machineGraphics machine
  Right machine {machineGraphics = graphics {currentOpacity = opacity}}

setLineWidth :: Machine -> Object -> Either BuildError Machine
setLineWidth machine value = do
  width <- number value
  let graphics = machineGraphics machine
  Right machine {machineGraphics = graphics {currentLineWidth = width}}
setMiterLimit :: Machine -> Object -> Either BuildError Machine
setMiterLimit machine value = do
  limit <- number value
  if limit < 1
    then Left (PdfStructureError "miter limit must be at least 1")
    else
      let graphics = machineGraphics machine
       in Right machine {machineGraphics = graphics {currentMiterLimit = limit}}
setDashPattern :: Machine -> Object -> Object -> Either BuildError Machine
setDashPattern machine valuesObject phaseObject = do
  values <- maybe (Left (PdfStructureError "dash pattern expected an array")) Right (arrayValue valuesObject)
  dashArray <- traverse number (Vector.toList values)
  dashPhase <- number phaseObject
  if any (< 0) dashArray
    then Left (PdfStructureError "dash array values must be nonnegative")
    else
      if not (null dashArray) && all (== 0) dashArray
        then Left (PdfStructureError "dash array must not contain only zeros")
        else
          let graphics = machineGraphics machine
           in Right machine {machineGraphics = graphics {currentDashArray = dashArray, currentDashPhase = dashPhase}}
setGray :: Bool -> Machine -> Object -> Either BuildError Machine
setGray isFill machine value = do
  gray <- number value
  setColor isFill GrayColorSpace machine (Color gray gray gray)
setRgb :: Bool -> Machine -> [Object] -> Either BuildError Machine
setRgb isFill machine values = case traverse number values of
  Right [red, green, blue] -> setColor isFill RgbColorSpace machine (Color red green blue)
  _ -> Left (PdfStructureError "RGB operator expected three numbers")
setCmyk :: Bool -> Machine -> [Object] -> Either BuildError Machine
setCmyk isFill machine values = case traverse number values of
  Right components@[cyan, magenta, yellow, black]
    | all validColorComponent components ->
        setColor isFill CmykColorSpace machine (Color (1 - min 1 (cyan + black)) (1 - min 1 (magenta + black)) (1 - min 1 (yellow + black)))
    | otherwise -> Left (PdfStructureError "CMYK components must be between 0 and 1")
  _ -> Left (PdfStructureError "CMYK operator expected four numbers")

validColorComponent :: Double -> Bool
validColorComponent value = value >= 0 && value <= 1
selectColorSpace :: Resources -> Bool -> Machine -> Object -> Either BuildError Machine
selectColorSpace resources isFill machine value = do
  name <- maybe (Left (PdfStructureError "color-space operator expected a name")) Right (nameValue value)
  colorSpace <- case deviceColorSpace name of
    Just device -> Right device
    Nothing -> case Map.lookup name (resourceColorSpaces resources) of
      Just (SupportedColorSpace supported) -> Right supported
      Just UnsupportedColorSpace -> Left (UnsupportedOperator ("unsupported named color space: " <> nameText name))
      Nothing -> Left (PdfStructureError ("missing color-space resource " <> nameText name))
  Right (updateColor isFill colorSpace (Color 0 0 0) machine)

setSelectedColor :: Bool -> Machine -> [Object] -> Either BuildError Machine
setSelectedColor isFill machine values = case selectedColorSpace isFill machine of
  GrayColorSpace -> case values of
    [value] -> setGray isFill machine value
    _ -> Left (PdfStructureError "gray color operator expected one number")
  RgbColorSpace -> setRgb isFill machine values
  CmykColorSpace -> setCmyk isFill machine values

selectedColorSpace :: Bool -> Machine -> DeviceColorSpace
selectedColorSpace isFill machine =
  let graphics = machineGraphics machine
   in if isFill then currentFillColorSpace graphics else currentStrokeColorSpace graphics

deviceColorSpace :: Name -> Maybe DeviceColorSpace
deviceColorSpace name = case nameText name of
  "DeviceGray" -> Just GrayColorSpace
  "DeviceRGB" -> Just RgbColorSpace
  "DeviceCMYK" -> Just CmykColorSpace
  _ -> Nothing

setColor :: Bool -> DeviceColorSpace -> Machine -> Color -> Either BuildError Machine
setColor isFill colorSpace machine color = Right (updateColor isFill colorSpace color machine)

updateColor :: Bool -> DeviceColorSpace -> Color -> Machine -> Machine
updateColor isFill colorSpace color machine =
  let graphics = machineGraphics machine
      updated =
        if isFill
          then graphics {currentFill = color, currentFillColorSpace = colorSpace}
          else graphics {currentStroke = color, currentStrokeColorSpace = colorSpace}
   in machine {machineGraphics = updated}
chunksOfTwo :: [a] -> [[a]]
chunksOfTwo [] = []
chunksOfTwo (first : second : rest) = [first, second] : chunksOfTwo rest
chunksOfTwo [_] = []

nameText :: Name -> Text
nameText = TextEncoding.decodeLatin1 . toByteString
