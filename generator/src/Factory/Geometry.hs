-- | Pure coordinate and matrix operations.
--
-- PDF places (0,0) at the bottom-left. Browsers place it at the top-left.
-- Keeping this conversion in one module gives the project one authoritative
-- answer to the most common source of misplaced links and images.
module Factory.Geometry
  ( applyMatrix
  , boardMatrix
  , identityMatrix
  , imagePresentationMatrix
  , multiplyMatrix
  , pdfPointToBoard
  , placeVectorPath
  , rectangleToBoard
  ) where

import Factory.Domain
  ( BoardSpace
  , Coordinate (Coordinate, unCoordinate)
  , ImageSpace
  , Matrix (Matrix)
  , PathCommand (ClosePath, CurveTo, LineTo, MoveTo)
  , PdfSpace
  , Point (Point)
  , Rect (Rect)
  , VectorContour (VectorContour)
  , VectorPath (vectorContours)
  , VectorSegment (VectorCubic, VectorLine)
  )

identityMatrix :: Matrix
identityMatrix = Matrix 1 0 0 1 0 0

-- | Apply the left matrix first, matching the PDF @cm@ operator.
multiplyMatrix :: Matrix -> Matrix -> Matrix
multiplyMatrix (Matrix a1 b1 c1 d1 e1 f1) (Matrix a2 b2 c2 d2 e2 f2) =
  Matrix
    (a1 * a2 + b1 * c2)
    (a1 * b2 + b1 * d2)
    (c1 * a2 + d1 * c2)
    (c1 * b2 + d1 * d2)
    (e1 * a2 + f1 * c2 + e2)
    (e1 * b2 + f1 * d2 + f2)

applyMatrix :: Matrix -> Point space -> Point space
applyMatrix (Matrix a b c d e f) (Point (Coordinate x) (Coordinate y)) =
  Point (Coordinate (a * x + c * y + e)) (Coordinate (b * x + d * y + f))

pdfPointToBoard :: Coordinate PdfSpace -> Point PdfSpace -> Point BoardSpace
pdfPointToBoard pageHeight (Point x y) =
  Point (coerceCoordinate x) (coerceCoordinate pageHeight - coerceCoordinate y)

-- | Convert a PDF matrix into the equivalent CSS matrix.
boardMatrix :: Coordinate PdfSpace -> Matrix -> Matrix
boardMatrix (Coordinate pageHeight) (Matrix a b c d e f) =
  Matrix a (-b) c (-d) e (pageHeight - f)

-- | Map image samples, rows counted from the top, from the unit square onto the board.
--
-- A PDF image matrix maps the unit square with its y axis growing up, so the
-- first sample row lies at y = 1. This is the only place that flips it.
imagePresentationMatrix :: Matrix -> Matrix
imagePresentationMatrix (Matrix a b c d e f) = Matrix a b (-c) (-d) (e + c) (f + d)

-- | Place traced image geometry with an image node's presentation matrix.
placeVectorPath :: Matrix -> VectorPath -> [PathCommand]
placeVectorPath matrix = concatMap contourCommands . vectorContours
  where
    contourCommands (VectorContour start segments) = MoveTo (place start) : map segmentCommand segments <> [ClosePath]
    segmentCommand (VectorLine point) = LineTo (place point)
    segmentCommand (VectorCubic first second end) = CurveTo (place first) (place second) (place end)
    place :: Point ImageSpace -> Point BoardSpace
    place (Point x y) = applyMatrix matrix (Point (coerceCoordinate x) (coerceCoordinate y))

rectangleToBoard :: Coordinate PdfSpace -> Rect PdfSpace -> Rect BoardSpace
rectangleToBoard height (Rect x y width rectangleHeight) =
  Rect
    (coerceCoordinate x)
    (coerceCoordinate height - coerceCoordinate y - coerceCoordinate rectangleHeight)
    (coerceCoordinate width)
    (coerceCoordinate rectangleHeight)

coerceCoordinate :: Coordinate from -> Coordinate to
coerceCoordinate = Coordinate . unCoordinate
