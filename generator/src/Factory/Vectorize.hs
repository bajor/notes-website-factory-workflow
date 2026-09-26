{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Deterministically classify and trace embedded Freeform artwork.
module Factory.Vectorize
  ( ArtworkPartition (..)
  , ImageDisposition (..)
  , classifyImage
  , opaqueHighlighter
  , partitionArtwork
  , traceImage
  , traceReconstructedImage
  , traceSmoothImage
  ) where

import Codec.Picture (Image, PixelRGBA8 (PixelRGBA8), generateImage, imageData, imageHeight, imageWidth, pixelAt)
import Control.Monad (foldM)
import Control.Monad.ST (runST)
import Data.ByteString (ByteString)
import Data.Int (Int32)
import Data.List (foldl', maximumBy, zip4)
import Data.Map.Strict (Map)
import Data.Maybe (catMaybes)
import Data.Ord (comparing)
import Data.Set (Set)
import Data.Text (Text)
import Data.Word (Word8)
import Factory.Domain
import Numeric (showFFloat)
import qualified Data.ByteString as ByteString
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Vector as Boxed
import qualified Data.Vector.Storable as Storable
import qualified Data.Vector.Unboxed as Unboxed
import qualified Data.Vector.Unboxed.Mutable as MUnboxed

data ImageDisposition = PreserveRaster | PreserveLowAlphaRaster | TraceAsVector
  deriving stock (Eq, Show)

-- | Traceable artwork split by connected component. Each part holds only its
-- components and is absent when it has none; a part holding every component
-- is the unchanged source image.
data ArtworkPartition = ArtworkPartition
  { tracedComponents :: Maybe (Image PixelRGBA8)
  , smoothedComponents :: Maybe (Image PixelRGBA8)
  , reconstructedComponents :: Maybe (Image PixelRGBA8)
  , residualComponents :: Maybe (Image PixelRGBA8)
  }
  deriving stock (Eq)

data ComponentKind = PixelTraced | SmoothTraced | ReconstructedStroke | RasterResidual
  deriving stock (Eq)

data ComponentColor = NoComponentColor | ComponentColor Word8 Word8 Word8 | MixedComponentColors
  deriving stock (Eq)

data Component = Component
  { componentPixels :: ![Int]
  , componentInk :: !Int
  , componentUntraced :: !Int
  , componentCovered :: !Int
  , componentBoundary :: !Int
  , componentColor :: !ComponentColor
  }

data Style = Style Word8 Word8 Word8 Word8
  deriving stock (Eq, Ord, Show)

data ContourPoint = ContourPoint Double Double
  deriving stock (Eq, Ord, Show)

data PixelProfile = PixelProfile
  { profileVisible :: Int
  , profileChromatic :: Int
  , profileLeft :: Int
  , profileTop :: Int
  , profileRight :: Int
  , profileBottom :: Int
  , profileHasTransparency :: Bool
  }

type GridPoint = ContourPoint

data Edge = Edge GridPoint GridPoint
  deriving stock (Eq, Ord, Show)

minimumTransparentFraction :: Double
minimumTransparentFraction = 0.02

maximumRasterTransparency :: Double
maximumRasterTransparency = 0.01

minimumTraceableAlpha :: Word8
minimumTraceableAlpha = 96

faintLayerOpacity :: Word8
faintLayerOpacity = 64

minimumVectorLayerAlpha :: Word8
minimumVectorLayerAlpha = 88

maximumVectorPoints :: Int
maximumVectorPoints = 500000

simplificationToleranceSquared :: Double
simplificationToleranceSquared = 0.25

minimumHighlighterAspect :: Int
minimumHighlighterAspect = 4

minimumHighlighterChroma :: Int
minimumHighlighterChroma = 28

maximumUntracedInkFraction :: Double
maximumUntracedInkFraction = 0.25

halfCoverageAlpha :: Int
halfCoverageAlpha = 128

maximumSmoothStrokeWidth :: Int
maximumSmoothStrokeWidth = 3

supersampling :: Int
supersampling = 4

smoothTileSize :: Int
smoothTileSize = 16

histogramBins :: Int
histogramBins = 5120

histogramBinWidth :: Double
histogramBinWidth = 0.0625

minimumCornerCosine :: Double
minimumCornerCosine = -0.5

minimumReconstructionPeak :: Int
minimumReconstructionPeak = 48

reconstructionLevel :: Double
reconstructionLevel = 0.6

normalizationRadius :: Int
normalizationRadius = 3

minimumNormalizedAlpha :: Double
minimumNormalizedAlpha = 24

classifyImage :: Maybe ByteString -> Either BuildError ImageDisposition
classifyImage Nothing = Right PreserveRaster
classifyImage (Just alpha)
  | ByteString.null alpha = Left (UnsupportedImage "soft mask is empty")
  | not hasNonzeroAlpha = Left (UnsupportedImage "soft mask contains no visible artwork")
  | not hasTraceableAlpha = Right PreserveLowAlphaRaster
  | transparentFraction <= maximumRasterTransparency = Right PreserveRaster
  | transparentFraction < minimumTransparentFraction = Left (UnsupportedImage "soft-masked image is too opaque to classify safely")
  | otherwise = Right TraceAsVector
  where
    samples = ByteString.unpack alpha
    hasNonzeroAlpha = any (> 0) samples
    hasTraceableAlpha = any (>= minimumTraceableAlpha) samples
    transparent = length (filter (< 255) samples)
    transparentFraction = fromIntegral transparent / fromIntegral (length samples)

opaqueHighlighter :: Image PixelRGBA8 -> Maybe (Image PixelRGBA8)
opaqueHighlighter image
  | visible == 0 = Nothing
  | profileChromatic profile * 20 < visible * 19 = Nothing
  | not (profileHasTransparency profile) = Nothing
  | longer < shorter * minimumHighlighterAspect = Nothing
  | otherwise = Just (generateImage opaquePixel (imageWidth image) (imageHeight image))
  where
    profile = imageProfile image
    visible = profileVisible profile
    width = profileRight profile - profileLeft profile
    height = profileBottom profile - profileTop profile
    longer = max width height
    shorter = max 1 (min width height)
    opaquePixel x y = case pixelAt image x y of
      PixelRGBA8 red green blue 0 -> PixelRGBA8 red green blue 0
      PixelRGBA8 red green blue _ -> PixelRGBA8 red green blue 255

imageProfile :: Image PixelRGBA8 -> PixelProfile
imageProfile image = rows 0 emptyProfile
  where
    emptyProfile = PixelProfile 0 0 (imageWidth image) (imageHeight image) 0 0 False
    rows y !profile
      | y == imageHeight image = profile
      | otherwise = rows (y + 1) (columns 0 y profile)
    columns x y !profile
      | x == imageWidth image = profile
      | otherwise = columns (x + 1) y (addPixel x y (pixelAt image x y) profile)

addPixel :: Int -> Int -> PixelRGBA8 -> PixelProfile -> PixelProfile
addPixel _ _ (PixelRGBA8 _ _ _ 0) profile = profile
addPixel x y (PixelRGBA8 red green blue alpha) profile =
  PixelProfile
    { profileVisible = profileVisible profile + 1
    , profileChromatic = profileChromatic profile + fromEnum (maximum channels - minimum channels >= minimumHighlighterChroma)
    , profileLeft = min x (profileLeft profile)
    , profileTop = min y (profileTop profile)
    , profileRight = max (x + 1) (profileRight profile)
    , profileBottom = max (y + 1) (profileBottom profile)
    , profileHasTransparency = profileHasTransparency profile || alpha < 255
    }
  where
    channels = map fromIntegral [red, green, blue] :: [Int]

-- | Split traceable artwork by how each connected component can be drawn.
--
-- Tracing retains only samples at or above 'minimumVectorLayerAlpha'. Strokes
-- narrower than a source pixel keep most of their ink below that alpha and
-- break apart when traced; narrow single-color ones are reconstructed as pen
-- strokes and the rest stay raster. Strokes up to about three pixels wide
-- trace coarsely at pixel resolution, so single-color ones are traced from a
-- supersampled field instead. Components are 8-connected, so no contour cell
-- spans two of them and separating one never changes another's trace.
partitionArtwork :: Image PixelRGBA8 -> ArtworkPartition
partitionArtwork image
  | all (== PixelTraced) kinds = ArtworkPartition (Just image) Nothing Nothing Nothing
  | all (== RasterResidual) kinds = ArtworkPartition Nothing Nothing Nothing (Just image)
  | otherwise =
      ArtworkPartition (selectComponents PixelTraced) (selectComponents SmoothTraced) (selectComponents ReconstructedStroke) (selectComponents RasterResidual)
  where
    (labels, components) = labelComponents image
    kinds = Boxed.fromList (map (componentKind image) components)
    width = imageWidth image
    selectComponents kind
      | kind `notElem` kinds = Nothing
      | otherwise = Just (generateImage pixel width (imageHeight image))
      where
        pixel x y = case labels Unboxed.! (y * width + x) of
          0 -> PixelRGBA8 0 0 0 0
          label
            | kinds Boxed.! (fromIntegral label - 1) == kind -> pixelAt image x y
            | otherwise -> PixelRGBA8 0 0 0 0

componentKind :: Image PixelRGBA8 -> Component -> ComponentKind
componentKind image component
  | untraceable, Just _ <- strokeColor image component = ReconstructedStroke
  | untraceable = RasterResidual
  | componentCovered component > 0
  , 2 * componentCovered component < maximumSmoothStrokeWidth * componentBoundary component
  , ComponentColor {} <- componentColor component =
      SmoothTraced
  | otherwise = PixelTraced
  where
    untraceable = fromIntegral (componentUntraced component) > maximumUntracedInkFraction * fromIntegral (componentInk component)

-- | The single color of a narrow stroke of opaque ink, if the component is one.
--
-- Measured over samples at or above half the component's own peak alpha: a
-- pen stroke narrower than a source pixel is narrow there whatever its peak,
-- while a translucent mark stays wide and a faint smudge stays below the peak
-- floor.
strokeColor :: Image PixelRGBA8 -> Component -> Maybe (Word8, Word8, Word8)
strokeColor image component
  | peak < minimumReconstructionPeak = Nothing
  | 2 * length significant >= maximumSmoothStrokeWidth * boundary = Nothing
  | otherwise = case foldl' mergeComponentColor NoComponentColor (map (quantizedColor . pixelAtIndex image) significant) of
      ComponentColor red green blue -> Just (red, green, blue)
      _ -> Nothing
  where
    pixels = componentPixels component
    peak = maximum (map (alphaIndex image) pixels)
    half = (peak + 1) `div` 2
    significant = filter ((>= half) . alphaIndex image) pixels
    boundary = length (filter (any (not . isSignificant) . pixelEdgeNeighbors (imageWidth image)) significant)
    isSignificant (x, y) = x >= 0 && y >= 0 && x < imageWidth image && y < imageHeight image && alphaIndex image (y * imageWidth image + x) >= half

-- | Label 8-connected visible components in row-major discovery order.
labelComponents :: Image PixelRGBA8 -> (Unboxed.Vector Int32, [Component])
labelComponents image = runST $ do
  labels <- MUnboxed.replicate pixelCount 0
  components <- scan labels 0 0 []
  frozen <- Unboxed.unsafeFreeze labels
  pure (frozen, reverse components)
  where
    width = imageWidth image
    height = imageHeight image
    pixelCount = width * height
    scan labels !index !count found
      | index == pixelCount = pure found
      | alphaIndex image index == 0 = scan labels (index + 1) count found
      | otherwise = do
          current <- MUnboxed.read labels index
          if current /= 0
            then scan labels (index + 1) count found
            else do
              let label = count + 1
              MUnboxed.write labels index label
              component <- fill labels label [index] emptyComponent
              scan labels (index + 1) label (component : found)
    fill labels label stack !component = case stack of
      [] -> pure component
      index : rest -> do
        next <- foldM (claim labels label) rest (neighbors index)
        fill labels label next (addComponentPixel image index component)
    claim labels label stack neighbor
      | alphaIndex image neighbor == 0 = pure stack
      | otherwise = do
          current <- MUnboxed.read labels neighbor
          if current /= 0
            then pure stack
            else neighbor : stack <$ MUnboxed.write labels neighbor label
    neighbors index =
      [ neighborY * width + neighborX
      | offsetY <- [-1, 0, 1]
      , offsetX <- [-1, 0, 1]
      , (offsetX, offsetY) /= (0, 0)
      , let neighborX = x + offsetX
            neighborY = y + offsetY
      , neighborX >= 0 && neighborX < width && neighborY >= 0 && neighborY < height
      ]
      where
        (y, x) = index `divMod` width

emptyComponent :: Component
emptyComponent = Component [] 0 0 0 0 NoComponentColor

addComponentPixel :: Image PixelRGBA8 -> Int -> Component -> Component
addComponentPixel image index component =
  Component
    { componentPixels = index : componentPixels component
    , componentInk = componentInk component + alpha
    , componentUntraced = componentUntraced component + (if alpha < fromIntegral minimumVectorLayerAlpha then alpha else 0)
    , componentCovered = componentCovered component + fromEnum covered
    , componentBoundary = componentBoundary component + fromEnum (covered && any (not . isCovered) (pixelEdgeNeighbors width index))
    , componentColor =
        if alpha < fromIntegral minimumVectorLayerAlpha
          then componentColor component
          else mergeComponentColor (componentColor component) (quantizedColor (pixelAtIndex image index))
    }
  where
    width = imageWidth image
    alpha = alphaIndex image index
    covered = alpha >= halfCoverageAlpha
    isCovered (neighborX, neighborY) =
      neighborX >= 0 && neighborX < width && neighborY >= 0 && neighborY < imageHeight image && alphaIndex image (neighborY * width + neighborX) >= halfCoverageAlpha

mergeComponentColor :: ComponentColor -> ComponentColor -> ComponentColor
mergeComponentColor NoComponentColor color = color
mergeComponentColor existing color
  | existing == color = existing
  | otherwise = MixedComponentColors

quantizedColor :: PixelRGBA8 -> ComponentColor
quantizedColor (PixelRGBA8 red green blue _) = ComponentColor (quantize 32 red) (quantize 32 green) (quantize 32 blue)

pixelEdgeNeighbors :: Int -> Int -> [(Int, Int)]
pixelEdgeNeighbors width index = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
  where
    (y, x) = index `divMod` width

pixelAtIndex :: Image PixelRGBA8 -> Int -> PixelRGBA8
pixelAtIndex image index = let (y, x) = index `divMod` imageWidth image in pixelAt image x y

alphaIndex :: Image PixelRGBA8 -> Int -> Int
alphaIndex image index = fromIntegral (imageData image Storable.! (index * 4 + 3))

-- | Trace single-color thin components from a bicubic supersampled field.
--
-- Each component's contour level preserves its ink area, so strokes keep the
-- source weight instead of the dilation of the pixel tracer's alpha floor.
-- Contours become Catmull-Rom cubic curves through the simplified points.
traceSmoothImage :: Image PixelRGBA8 -> Either BuildError [VectorShape]
traceSmoothImage image =
  curveShapes image "smoothed artwork contains no visible shapes" $
    [ ((red, green, blue), smoothContours image labels label component)
    | (label, component) <- zip [1 ..] components
    , ComponentColor red green blue <- [componentColor component]
    ]
  where
    (labels, components) = labelComponents image

-- | Redraw narrow sub-pixel strokes as crisp vector ink.
--
-- A stroke narrower than a source pixel has an uneven peak alpha along its
-- length, so any single contour level either breaks or bloats it. Dividing the
-- supersampled field by its local maximum brings every point of the stroke's
-- ridge to about one, and the contour at 'reconstructionLevel' of that ridge
-- follows the stroke continuously. The result is drawn as opaque ink.
traceReconstructedImage :: Image PixelRGBA8 -> Either BuildError [VectorShape]
traceReconstructedImage image =
  curveShapes image "reconstructed artwork contains no visible shapes" $
    [ (color, reconstructedContours image labels label component)
    | (label, component) <- zip [1 ..] components
    , Just color <- [strokeColor image component]
    ]
  where
    (labels, components) = labelComponents image

curveShapes :: Image PixelRGBA8 -> Text -> [((Word8, Word8, Word8), [[GridPoint]])] -> Either BuildError [VectorShape]
curveShapes image emptyMessage traced
  | null shapes = Left (UnsupportedImage emptyMessage)
  | pointCount > maximumVectorPoints = Left (UnsupportedImage "vector artwork exceeds the point complexity limit")
  | otherwise = Right shapes
  where
    shapes =
      [ VectorShape
          { vectorPath = VectorPath (curvePathText (imageWidth image) (imageHeight image) contours)
          , vectorColor = styleColor (Style red green blue 255)
          , vectorOpacity = 1
          }
      | ((red, green, blue), contours@(_ : _)) <- traced
      ]
    pointCount = sum [length contour | (_, contours) <- traced, contour <- contours]

smoothContours :: Image PixelRGBA8 -> Unboxed.Vector Int32 -> Int32 -> Component -> [[GridPoint]]
smoothContours image labels label component = traceContours edges
  where
    width = imageWidth image
    tiles = map (fieldTile (componentAlpha image labels label)) (componentTiles width component)
    targetSamples = componentInk component * supersampling * supersampling `div` 255
    level = areaLevel targetSamples (sampleHistogram tiles)
    edges = Set.unions (map (tileEdges width (imageHeight image) level) tiles)

reconstructedContours :: Image PixelRGBA8 -> Unboxed.Vector Int32 -> Int32 -> Component -> [[GridPoint]]
reconstructedContours image labels label component = traceContours edges
  where
    width = imageWidth image
    tiles = map (normalizedTile (componentAlpha image labels label)) (componentTiles width component)
    edges = Set.unions (map (tileEdges width (imageHeight image) reconstructionLevel) tiles)

-- | Alpha of one labeled component, zero elsewhere and outside the image.
componentAlpha :: Image PixelRGBA8 -> Unboxed.Vector Int32 -> Int32 -> Int -> Int -> Double
componentAlpha image labels label x y
  | x < 0 || y < 0 || x >= width || y >= imageHeight image = 0
  | labels Unboxed.! index /= label = 0
  | otherwise = fromIntegral (alphaIndex image index)
  where
    width = imageWidth image
    index = y * width + x

data FieldTile = FieldTile Int Int (Unboxed.Vector Double)

tileSide :: Int
tileSide = smoothTileSize * supersampling + 1

-- | Tiles within the bicubic support of a component; other tiles are zero.
componentTiles :: Int -> Component -> [(Int, Int)]
componentTiles width component =
  Set.toAscList
    ( Set.fromList
        [ (tileX, tileY)
        | index <- componentPixels component
        , let (y, x) = index `divMod` width
        , tileY <- [(y - tileMargin) `div` smoothTileSize .. (y + tileMargin) `div` smoothTileSize]
        , tileX <- [(x - tileMargin) `div` smoothTileSize .. (x + tileMargin) `div` smoothTileSize]
        ]
    )
  where
    tileMargin = 3

fieldTile :: (Int -> Int -> Double) -> (Int, Int) -> FieldTile
fieldTile alphaAt (tileX, tileY) = FieldTile originX originY (Unboxed.generate (tileSide * tileSide) sample)
  where
    originX = tileX * smoothTileSize * supersampling
    originY = tileY * smoothTileSize * supersampling
    sample offset =
      let (row, column) = offset `divMod` tileSide
       in bicubicSample alphaAt (originX + column) (originY + row)

-- | A field tile divided by the maximum of its square neighborhood.
--
-- The tile is evaluated with a margin of 'normalizationRadius' samples so each
-- inner sample sees its whole neighborhood and shared tile borders agree.
-- Samples whose neighborhood peak is below 'minimumNormalizedAlpha' stay zero.
normalizedTile :: (Int -> Int -> Double) -> (Int, Int) -> FieldTile
normalizedTile alphaAt (tileX, tileY) = FieldTile originX originY (Unboxed.generate (tileSide * tileSide) normalized)
  where
    originX = tileX * smoothTileSize * supersampling
    originY = tileY * smoothTileSize * supersampling
    radius = normalizationRadius
    side = tileSide + 2 * radius
    extended = Unboxed.generate (side * side) $ \offset ->
      let (row, column) = offset `divMod` side
       in max 0 (bicubicSample alphaAt (originX - radius + column) (originY - radius + row))
    rowMaxima = Unboxed.generate (side * side) $ \offset ->
      let (row, column) = offset `divMod` side
       in maximum [extended Unboxed.! (row * side + neighbor) | neighbor <- [max 0 (column - radius) .. min (side - 1) (column + radius)]]
    normalized offset =
      let (row, column) = offset `divMod` tileSide
          value = extended Unboxed.! ((row + radius) * side + column + radius)
          peak = maximum [rowMaxima Unboxed.! ((row + neighbor) * side + column + radius) | neighbor <- [0 .. 2 * radius]]
       in if peak < minimumNormalizedAlpha then 0 else value / peak

-- | Keys bicubic interpolation of source samples at a supersampled position.
bicubicSample :: (Int -> Int -> Double) -> Int -> Int -> Double
bicubicSample alphaAt sampleX sampleY =
  sum
    [ cubicWeight (u - fromIntegral x) * cubicWeight (v - fromIntegral y) * alphaAt x y
    | y <- [baseY - 1 .. baseY + 2]
    , x <- [baseX - 1 .. baseX + 2]
    ]
  where
    u = supersampledCenter sampleX
    v = supersampledCenter sampleY
    baseX = floor u
    baseY = floor v

-- | Source sample-index coordinate of a supersampled sample center.
supersampledCenter :: Int -> Double
supersampledCenter sample = (fromIntegral sample + 0.5) / fromIntegral supersampling - 0.5

cubicWeight :: Double -> Double
cubicWeight offset
  | distance <= 1 = (1.5 * distance - 2.5) * distance * distance + 1
  | distance < 2 = ((-0.5 * distance + 2.5) * distance - 4) * distance + 2
  | otherwise = 0
  where
    distance = abs offset

sampleHistogram :: [FieldTile] -> Unboxed.Vector Int
sampleHistogram tiles =
  Unboxed.accum (+) (Unboxed.replicate histogramBins 0) [(bin value, 1) | FieldTile _ _ values <- tiles, (offset, value) <- zip [0 ..] (Unboxed.toList values), owned offset, value > 0]
  where
    owned offset = let (row, column) = offset `divMod` tileSide in row < tileSide - 1 && column < tileSide - 1
    bin value = min (histogramBins - 1) (floor (value / histogramBinWidth))

-- | The lowest histogram level whose covered sample count reaches the target.
areaLevel :: Int -> Unboxed.Vector Int -> Double
areaLevel target histogram = go (Unboxed.length histogram - 1) 0
  where
    go bin covered
      | bin <= 0 = histogramBinWidth
      | reached >= target = fromIntegral bin * histogramBinWidth
      | otherwise = go (bin - 1) reached
      where
        reached = covered + histogram Unboxed.! bin

tileEdges :: Int -> Int -> Double -> FieldTile -> Set Edge
tileEdges width height level (FieldTile originX originY values) =
  Set.fromList [edge | row <- [0 .. tileSide - 2], column <- [0 .. tileSide - 2], edge <- cellEdges column row]
  where
    valueAt column row = values Unboxed.! (row * tileSide + column)
    cellEdges column row =
      [ canonicalEdge start end
      | (firstEdge, secondEdge) <- segmentsFor mask
      , let start = edgePoint firstEdge
            end = edgePoint secondEdge
      , start /= end
      ]
      where
        topLeft = valueAt column row
        topRight = valueAt (column + 1) row
        bottomRight = valueAt (column + 1) (row + 1)
        bottomLeft = valueAt column (row + 1)
        bit value weight = if value >= level then weight else 0
        mask = bit topLeft 1 + bit topRight 2 + bit bottomRight 4 + bit bottomLeft 8
        edgePoint edgeNumber = case edgeNumber of
          0 -> crossing column row (column + 1) row topLeft topRight
          1 -> crossing (column + 1) row (column + 1) (row + 1) topRight bottomRight
          2 -> crossing column (row + 1) (column + 1) (row + 1) bottomLeft bottomRight
          _ -> crossing column row column (row + 1) topLeft bottomLeft
    crossing startColumn startRow endColumn endRow startValue endValue =
      let factor = (level - startValue) / (endValue - startValue)
          ContourPoint startX startY = samplePoint startColumn startRow
          ContourPoint endX endY = samplePoint endColumn endRow
       in clampToImage (ContourPoint (startX + factor * (endX - startX)) (startY + factor * (endY - startY)))
    samplePoint column row = ContourPoint (sampleEdge (originX + column)) (sampleEdge (originY + row))
    sampleEdge sample = (fromIntegral sample + 0.5) / fromIntegral supersampling
    clampToImage (ContourPoint x y) = ContourPoint (max 0 (min (fromIntegral width) x)) (max 0 (min (fromIntegral height) y))

traceImage :: Image PixelRGBA8 -> Either BuildError [VectorShape]
traceImage image
  | null shapes = Left (UnsupportedImage "vector artwork contains no visible shapes")
  | pointCount > maximumVectorPoints = Left (UnsupportedImage "vector artwork exceeds the point complexity limit")
  | otherwise = Right shapes
  where
    boundaries = collectBoundaries image
    contours = [(style, traceContours edges) | (style, edges) <- Map.toAscList boundaries]
    shapes = map (shapeFromContours (imageWidth image) (imageHeight image)) contours
    pointCount = sum [length contour | (_, styleContours) <- contours, contour <- styleContours]

collectBoundaries :: Image PixelRGBA8 -> Map Style (Set Edge)
collectBoundaries image = rows (-1) Map.empty
  where
    width = imageWidth image
    height = imageHeight image
    rows y boundaries
      | y == height = boundaries
      | otherwise = rows (y + 1) (columns (-1) y boundaries)
    columns x y boundaries
      | x == width = boundaries
      | otherwise = columns (x + 1) y (foldl' (addStyle x y) boundaries (cellStyles x y))
    addStyle x y boundaries style = foldl' (insertEdge style) boundaries (cellEdges style x y)
    cellStyles x y = Set.toAscList (Set.fromList (catMaybes [styleAt x y, styleAt (x + 1) y, styleAt (x + 1) (y + 1), styleAt x (y + 1)]))
    cellEdges style x y = mapMaybeEdge (segmentsFor mask)
      where
        topLeft = alphaAt style x y
        topRight = alphaAt style (x + 1) y
        bottomRight = alphaAt style (x + 1) (y + 1)
        bottomLeft = alphaAt style x (y + 1)
        traceAlpha = contourAlpha style
        boolBit alpha bit = if alpha >= traceAlpha then bit else 0
        mask = boolBit topLeft 1 + boolBit topRight 2 + boolBit bottomRight 4 + boolBit bottomLeft 8
        mapMaybeEdge = foldr add []
        add (firstEdge, secondEdge) edges = case (edgePoint firstEdge, edgePoint secondEdge) of
          (start, end)
            | start == end -> edges
            | otherwise -> canonicalEdge start end : edges
        edgePoint edge = case edge of
          0 -> interpolate traceAlpha x y (x + 1) y topLeft topRight
          1 -> interpolate traceAlpha (x + 1) y (x + 1) (y + 1) topRight bottomRight
          2 -> interpolate traceAlpha x (y + 1) (x + 1) (y + 1) bottomLeft bottomRight
          _ -> interpolate traceAlpha x y x (y + 1) topLeft bottomLeft
    styleAt x y = pixelAtMaybe x y >>= pixelStyle
    alphaAt style x y = case pixelAtMaybe x y of
      Just pixel@(PixelRGBA8 _ _ _ alpha)
        | quantizedStyle pixel == style || (alpha < minimumVectorLayerAlpha && sameColor style (quantizedStyle pixel)) -> fromIntegral alpha
      _ -> 0
    pixelAtMaybe x y
      | x < 0 || y < 0 || x >= width || y >= height = Nothing
      | otherwise = Just (pixelAt image x y)
    samplePoint x y = ContourPoint (fromIntegral x + 0.5) (fromIntegral y + 0.5)
    interpolate traceAlpha startX startY endX endY startAlpha endAlpha
      | Just (firstStyle, secondStyle) <- styleBoundary, sameColor firstStyle secondStyle =
          crossing ((contourAlpha firstStyle `max` contourAlpha secondStyle) - sourceAlpha startX startY) (sourceAlpha endX endY - sourceAlpha startX startY)
      | Just _ <- styleBoundary = midpoint
      | otherwise = crossing (traceAlpha - startAlpha) (endAlpha - startAlpha)
      where
        ContourPoint firstX firstY = samplePoint startX startY
        ContourPoint secondX secondY = samplePoint endX endY
        crossing numerator denominator =
          let factor = numerator / denominator
           in clampPoint (ContourPoint (firstX + factor * (secondX - firstX)) (firstY + factor * (secondY - firstY)))
        midpoint = ContourPoint ((firstX + secondX) / 2) ((firstY + secondY) / 2)
        styleBoundary = case (styleAt startX startY, styleAt endX endY) of
          (Just firstStyle, Just secondStyle) | firstStyle /= secondStyle -> Just (firstStyle, secondStyle)
          _ -> Nothing
    sourceAlpha x y = case pixelAtMaybe x y of
      Just (PixelRGBA8 _ _ _ alpha) -> fromIntegral alpha
      Nothing -> 0
    clampPoint (ContourPoint x y) = ContourPoint (max 0 (min (fromIntegral width) x)) (max 0 (min (fromIntegral height) y))

contourAlpha :: Style -> Double
contourAlpha (Style _ _ _ opacity) = fromIntegral lowerAlpha - halfAlphaSample
  where
    lowerAlpha = if opacity == faintLayerOpacity then minimumVectorLayerAlpha else minimumTraceableAlpha
    halfAlphaSample = 0.5

sameColor :: Style -> Style -> Bool
sameColor (Style red green blue _) (Style otherRed otherGreen otherBlue _) =
  (red, green, blue) == (otherRed, otherGreen, otherBlue)

segmentsFor :: Int -> [(Int, Int)]
segmentsFor mask = case mask of
  0 -> []
  1 -> [(3, 0)]
  2 -> [(0, 1)]
  3 -> [(3, 1)]
  4 -> [(1, 2)]
  5 -> [(3, 0), (1, 2)]
  6 -> [(0, 2)]
  7 -> [(3, 2)]
  8 -> [(2, 3)]
  9 -> [(0, 2)]
  10 -> [(0, 1), (2, 3)]
  11 -> [(1, 2)]
  12 -> [(1, 3)]
  13 -> [(0, 1)]
  14 -> [(3, 0)]
  _ -> []

canonicalEdge :: GridPoint -> GridPoint -> Edge
canonicalEdge start end
  | start <= end = Edge start end
  | otherwise = Edge end start

insertEdge :: Style -> Map Style (Set Edge) -> Edge -> Map Style (Set Edge)
insertEdge style boundaries edge = Map.insertWith Set.union style (Set.singleton edge) boundaries

pixelStyle :: PixelRGBA8 -> Maybe Style
pixelStyle pixel@(PixelRGBA8 _ _ _ alpha)
  | alpha < minimumVectorLayerAlpha = Nothing
  | otherwise = Just (quantizedStyle pixel)

quantizedStyle :: PixelRGBA8 -> Style
quantizedStyle (PixelRGBA8 red green blue alpha) =
  Style (quantize 32 red) (quantize 32 green) (quantize 32 blue) (quantizeOpacity alpha)

quantizeOpacity :: Word8 -> Word8
quantizeOpacity alpha
  | alpha < minimumTraceableAlpha = faintLayerOpacity
  | otherwise = 255

quantize :: Int -> Word8 -> Word8
quantize step value = fromIntegral (min 255 (((fromIntegral value + step `div` 2) `div` step) * step) :: Int)

shapeFromContours :: Int -> Int -> (Style, [[GridPoint]]) -> VectorShape
shapeFromContours width height (style, contours) =
  VectorShape
    { vectorPath = VectorPath (pathText width height contours)
    , vectorColor = styleColor style
    , vectorOpacity = styleOpacity style
    }

traceContours :: Set Edge -> [[GridPoint]]
traceContours = consumeContours . edgeMap

edgeMap :: Set Edge -> Map GridPoint (Set GridPoint)
edgeMap = Set.foldl' add Map.empty
  where
    add adjacency (Edge start end) = Map.insertWith Set.union end (Set.singleton start) (Map.insertWith Set.union start (Set.singleton end) adjacency)

consumeContours :: Map GridPoint (Set GridPoint) -> [[GridPoint]]
consumeContours adjacency
  | Map.null adjacency = []
  | otherwise =
      let (start, destinations) = Map.findMin adjacency
          next = Set.findMin destinations
          remaining = removeConnection start next adjacency
          (contour, rest) = walkContour start next [start] remaining
       in simplifyClosed contour : consumeContours rest

walkContour :: GridPoint -> GridPoint -> [GridPoint] -> Map GridPoint (Set GridPoint) -> ([GridPoint], Map GridPoint (Set GridPoint))
walkContour origin current reversed remaining
  | current == origin = (reverse reversed, remaining)
  | otherwise = case Map.lookup current remaining of
      Nothing -> (reverse (current : reversed), remaining)
      Just destinations ->
        let next = Set.findMin destinations
         in walkContour origin next (current : reversed) (removeConnection current next remaining)

removeConnection :: GridPoint -> GridPoint -> Map GridPoint (Set GridPoint) -> Map GridPoint (Set GridPoint)
removeConnection start end = remove end start . remove start end
  where
    remove point destination = Map.update removeDestination point
      where
        removeDestination destinations =
          let remaining = Set.delete destination destinations
           in if Set.null remaining then Nothing else Just remaining

simplifyClosed :: [GridPoint] -> [GridPoint]
simplifyClosed points
  | length cleaned <= 4 = cleaned
  | signedArea simplified * signedArea cleaned > 0 = simplified
  | otherwise = cleaned
  where
    cleaned = removeCollinear points
    simplified = init (simplifyOpen firstHalf) <> init (simplifyOpen secondHalf)
    anchor = head cleaned
    farthestIndex = fst (maximumBy (comparing (distanceSquared anchor . snd)) (zip [0 ..] cleaned))
    firstHalf = take (farthestIndex + 1) cleaned
    secondHalf = drop farthestIndex cleaned <> [anchor]

signedArea :: [GridPoint] -> Double
signedArea [] = 0
signedArea points = sum [x * nextY - nextX * y | (ContourPoint x y, ContourPoint nextX nextY) <- zip points (tail points <> [head points])]

simplifyOpen :: [GridPoint] -> [GridPoint]
simplifyOpen points
  | length points <= 2 = points
  | maximumDistance <= simplificationToleranceSquared = [start, end]
  | otherwise = init (simplifyOpen left) <> simplifyOpen right
  where
    start = head points
    end = last points
    middle = zip [1 ..] (tail (init points))
    (relativeIndex, _) = maximumBy (comparing (lineDistanceSquared start end . snd)) middle
    maximumDistance = lineDistanceSquared start end (points !! relativeIndex)
    left = take (relativeIndex + 1) points
    right = drop relativeIndex points

removeCollinear :: [GridPoint] -> [GridPoint]
removeCollinear points =
  [ current
  | (previous, current, next) <- zip3 (last points : init points) points (tail points <> [head points])
  , not (collinear previous current next)
  ]

collinear :: GridPoint -> GridPoint -> GridPoint -> Bool
collinear (ContourPoint ax ay) (ContourPoint bx by) (ContourPoint cx cy) =
  abs ((bx - ax) * (cy - by) - (by - ay) * (cx - bx)) <= 1.0e-9

distanceSquared :: GridPoint -> GridPoint -> Double
distanceSquared (ContourPoint ax ay) (ContourPoint bx by) =
  (bx - ax) ^ (2 :: Int) + (by - ay) ^ (2 :: Int)

lineDistanceSquared :: GridPoint -> GridPoint -> GridPoint -> Double
lineDistanceSquared (ContourPoint ax ay) (ContourPoint bx by) (ContourPoint px py)
  | lengthSquared == 0 = distanceSquared (ContourPoint ax ay) (ContourPoint px py)
  | otherwise = cross * cross / lengthSquared
  where
    dx = bx - ax
    dy = by - ay
    offsetX = px - ax
    offsetY = py - ay
    cross = dy * offsetX - dx * offsetY
    lengthSquared = dx * dx + dy * dy

pathText :: Int -> Int -> [[GridPoint]] -> Text
pathText width height = Text.intercalate " " . map contourText
  where
    contourText [] = ""
    contourText (point : rest) = "M" <> pointText point <> foldMap (("L" <>) . pointText) rest <> "Z"
    pointText (ContourPoint x y) = decimal width (x / fromIntegral width) <> "," <> decimal height (y / fromIntegral height)

-- | Closed cubic curves through each contour's points.
--
-- Each point's tangent follows its neighbors, as in a Catmull-Rom spline, but
-- handles reach only a third of their own segment so short features beside
-- long straight runs cannot loop. Turns sharper than 'minimumCornerCosine'
-- remain corners.
curvePathText :: Int -> Int -> [[GridPoint]] -> Text
curvePathText width height = Text.intercalate " " . map contourText
  where
    contourText points@(first : _ : _ : _) =
      "M" <> pointText first <> foldMap segmentText (zip4 points (rotate 1 points) tangents (rotate 1 tangents)) <> "Z"
      where
        tangents = zipWith3 tangentAt (rotate (-1) points) points (rotate 1 points)
    contourText points = pathText width height [points]
    segmentText (start, end, startTangent, endTangent) =
      "C" <> pointText (handle start startTangent reach) <> " " <> pointText (handle end endTangent (negate reach)) <> " " <> pointText end
      where
        reach = sqrt (distanceSquared start end) / 3
    rotate steps points = let count = length points in take count (drop (steps `mod` count) (cycle points))
    pointText (ContourPoint x y) = decimal width (x / fromIntegral width) <> "," <> decimal height (y / fromIntegral height)

data Tangent = Corner | Direction Double Double

tangentAt :: GridPoint -> GridPoint -> GridPoint -> Tangent
tangentAt previous current next = case (unitVector previous current, unitVector current next, unitVector previous next) of
  (Just (inX, inY), Just (outX, outY), Just (directionX, directionY))
    | inX * outX + inY * outY >= minimumCornerCosine -> Direction directionX directionY
  _ -> Corner

unitVector :: GridPoint -> GridPoint -> Maybe (Double, Double)
unitVector start@(ContourPoint startX startY) end@(ContourPoint endX endY)
  | size == 0 = Nothing
  | otherwise = Just ((endX - startX) / size, (endY - startY) / size)
  where
    size = sqrt (distanceSquared start end)

handle :: GridPoint -> Tangent -> Double -> GridPoint
handle point Corner _ = point
handle (ContourPoint x y) (Direction directionX directionY) reach = ContourPoint (x + directionX * reach) (y + directionY * reach)

decimal :: Int -> Double -> Text
decimal extent value = trimDecimal (Text.pack (showFFloat (Just precision) value ""))
  where
    precision = max minimumCoordinateDecimals (length (show extent) + subpixelDecimalPlaces)
    minimumCoordinateDecimals = 6
    subpixelDecimalPlaces = 2

trimDecimal :: Text -> Text
trimDecimal value =
  let withoutZeros = Text.dropWhileEnd (== '0') value
   in if Text.isSuffixOf "." withoutZeros then Text.dropEnd 1 withoutZeros else withoutZeros

styleColor :: Style -> Color
styleColor (Style red green blue _) = Color (channel red) (channel green) (channel blue)
  where
    channel = (/ 255) . fromIntegral

styleOpacity :: Style -> Double
styleOpacity (Style _ _ _ alpha) = fromIntegral alpha / 255
