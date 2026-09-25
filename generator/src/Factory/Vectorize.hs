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
  ) where

import Codec.Picture (Image, PixelRGBA8 (PixelRGBA8), generateImage, imageData, imageHeight, imageWidth, pixelAt)
import Control.Monad (foldM)
import Control.Monad.ST (runST)
import Data.ByteString (ByteString)
import Data.Int (Int32)
import Data.List (foldl', maximumBy)
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
import qualified Data.Vector.Storable as Storable
import qualified Data.Vector.Unboxed as Unboxed
import qualified Data.Vector.Unboxed.Mutable as MUnboxed

data ImageDisposition = PreserveRaster | PreserveLowAlphaRaster | TraceAsVector
  deriving stock (Eq, Show)

-- | Traceable artwork split by connected component. Mixed artwork carries the
-- traceable components first and the untraceable raster residual second.
data ArtworkPartition
  = TraceableArtwork (Image PixelRGBA8)
  | UntraceableArtwork (Image PixelRGBA8)
  | MixedArtwork (Image PixelRGBA8) (Image PixelRGBA8)
  deriving stock (Eq)

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

-- | Keep components as raster when tracing would drop too much of their ink.
--
-- Tracing retains only samples at or above 'minimumVectorLayerAlpha'. Strokes
-- narrower than a source pixel keep most of their ink below that alpha and
-- break apart when traced. Components are 8-connected, so no contour cell
-- spans two of them and removing one never changes another's trace.
partitionArtwork :: Image PixelRGBA8 -> ArtworkPartition
partitionArtwork image
  | not (Unboxed.or untraceable) = TraceableArtwork image
  | Unboxed.and untraceable = UntraceableArtwork image
  | otherwise = MixedArtwork (selectComponents not) (selectComponents id)
  where
    (labels, untraceable) = componentTraceability image
    width = imageWidth image
    selectComponents keep = generateImage pixel width (imageHeight image)
      where
        pixel x y = case labels Unboxed.! (y * width + x) of
          0 -> PixelRGBA8 0 0 0 0
          label
            | keep (untraceable Unboxed.! (fromIntegral label - 1)) -> pixelAt image x y
            | otherwise -> PixelRGBA8 0 0 0 0

-- | Label 8-connected visible components and flag those that are untraceable.
componentTraceability :: Image PixelRGBA8 -> (Unboxed.Vector Int32, Unboxed.Vector Bool)
componentTraceability image = runST $ do
  labels <- MUnboxed.replicate pixelCount 0
  flags <- scan labels 0 0 []
  frozen <- Unboxed.unsafeFreeze labels
  pure (frozen, Unboxed.fromList (reverse flags))
  where
    width = imageWidth image
    height = imageHeight image
    pixelCount = width * height
    alphaAt index = fromIntegral (imageData image Storable.! (index * 4 + 3)) :: Int
    scan labels !index !count flags
      | index == pixelCount = pure flags
      | alphaAt index == 0 = scan labels (index + 1) count flags
      | otherwise = do
          current <- MUnboxed.read labels index
          if current /= 0
            then scan labels (index + 1) count flags
            else do
              let label = count + 1
              MUnboxed.write labels index label
              (ink, untraced) <- fill labels label [index] 0 0
              scan labels (index + 1) label (isUntraceable ink untraced : flags)
    fill labels label stack !ink !untraced = case stack of
      [] -> pure (ink, untraced)
      index : rest -> do
        let alpha = alphaAt index
            untracedAlpha = if alpha < fromIntegral minimumVectorLayerAlpha then alpha else 0
        next <- foldM (claim labels label) rest (neighbors index)
        fill labels label next (ink + alpha) (untraced + untracedAlpha)
    claim labels label stack neighbor
      | alphaAt neighbor == 0 = pure stack
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

isUntraceable :: Int -> Int -> Bool
isUntraceable ink untraced = fromIntegral untraced > maximumUntracedInkFraction * fromIntegral ink

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
