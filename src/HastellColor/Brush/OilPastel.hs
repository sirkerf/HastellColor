-- | Oil pastel settings and state, independent of rendering backends.
module HastellColor.Brush.OilPastel
  ( OilPastel (..)
  , PastelState (..)
  , drawStroke
  ) where

import HastellColor.Color (RGB (..), blendRGB, clampRGB)
import qualified HastellColor.Brush.Kernel as Kernel
import HastellColor.Paper (Paper (..), PaperCell (..), PaperSettings (..), surfaceHeights)
import HastellColor.Stroke (Point (..), Stroke (..), StrokeSample (..), interpolateSample)

-- | Radius is measured in paper-cell units and must be positive.
data OilPastel = OilPastel
  { pastelColor :: RGB
  , pastelRadius :: Double
  -- | Total pigment in a fresh stick, in fully covered cell equivalents.
  , pastelCapacity :: Double
  }
  deriving (Eq, Show)

-- | Quantities passed through pure state transitions.
-- Both values are normalized to [0, 1]. A fresh stick has load 1 and wear 0.
data PastelState = PastelState
  { pastelPigmentLoad :: Double
  , pastelWear :: Double
  }
  deriving (Eq, Show)

-- | Sweep line segments over paper cells, then deposit pigment in one pure step.
-- A stroke uses the maximum contact at each cell to avoid dependence on input
-- sample density. Separate calls accumulate coats; retracing within one call
-- does not. Supply and wear are updated once per stroke in this initial model.
drawStroke :: OilPastel -> PastelState -> Stroke -> Paper -> Either String (Paper, PastelState)
drawStroke pastel state (Stroke samples) paper
  | not validPastel = Left "Pastel radius and capacity must be positive and finite; color must be finite."
  | not (unit load && unit wear) = Left "Pastel load and wear must be in [0, 1]."
  | not (all validSample samples) = Left "Stroke values must be finite, pressure in [0, 1], and altitude in [0, pi/2]."
  | not validPaper = Left "Paper dimensions, cell count, or cell values are invalid."
  | null samples || load == 0 = Right (paper, state)
  | otherwise = Right (paper {paperCells = paintedCells}, nextState)
  where
    settings = paperSettings paper
    cells = paperCells paper
    width = paperWidth settings
    height = paperHeight settings
    load = pastelPigmentLoad state
    wear = pastelWear state
    capacity = pastelCapacity pastel
    radius = pastelRadius pastel * (1 + 0.2 * wear)
    color = clampRGB (pastelColor pastel)
    validPastel =
      all (\value -> finite value && value > 0) [pastelRadius pastel, capacity]
        && finiteColor (pastelColor pastel)
    validPaper = width > 0 && height > 0
      && toInteger (length cells) == toInteger width * toInteger height
      && finiteColor (paperBaseColor settings)
      && all (\cell -> unit (cellHeight cell) && unit (cellPigmentAmount cell)
                        && finiteColor (cellPigmentColor cell)) cells
    validSample sample =
      let Point x y = samplePosition sample
          altitude = sampleAltitude sample
       in all finite [x, y, altitude, sampleAzimuth sample]
            && unit (samplePressure sample) && altitude >= 0 && altitude <= pi / 2
    segments = case samples of
      [sample] -> [(sample, sample)]
      _ -> zip samples (drop 1 samples)
    requests =
      [ Kernel.depositAmount (cellPigmentAmount cell) (contactAt position heightAtCell)
      | (index, cell, heightAtCell) <- zip3 [0 :: Int ..] cells (surfaceHeights paper)
      , let position = Point (fromIntegral (index `mod` width) + 0.5)
                             (fromIntegral (index `div` width) + 0.5)
      ]
    contactAt position heightAtCell = foldl' max 0
      [ let (edge, pressure) = segmentContact radius position start end
         in Kernel.grainContact heightAtCell pressure edge
      | (start, end) <- segments
      ]
    requested = foldl' (+) 0 requests
    available = load * capacity
    supplyScale = if requested <= 0 then 0 else min 1 (available / requested)
    used = min requested available
    paintedCells = zipWith deposit cells requests
    deposit cell request
      | amount <= 0 = cell
      | otherwise = cell
          { cellPigmentColor = blendRGB (amount / total) (cellPigmentColor cell) color
          , cellPigmentAmount = clampUnit total
          }
      where
        amount = request * supplyScale
        total = cellPigmentAmount cell + amount
    nextState = PastelState
      { pastelPigmentLoad = clampUnit (load - used / capacity)
      , pastelWear = clampUnit (wear + used / capacity)
      }

-- Sweep an oriented ellipse. For constant pressure/orientation, projection
-- in ellipse coordinates gives the exact swept footprint. Varying inputs use
-- a local ellipse approximation at the Euclidean projection, then interpolate
-- again at the refined fraction. This is not a time-resolved contact solver.
segmentContact :: Double -> Point -> StrokeSample -> StrokeSample -> (Double, Double)
segmentContact radius (Point x y) start end = (edge, samplePressure contact)
  where
    Point ax ay = samplePosition start
    Point bx by = samplePosition end
    dx = bx - ax
    dy = by - ay
    reference = interpolateSample (project (x - ax, y - ay) (dx, dy)) start end
    fraction = project (local reference (x - ax, y - ay)) (local reference (dx, dy))
    contact = interpolateSample fraction start end
    Point closestX closestY = samplePosition contact
    (u, v) = local contact (x - closestX, y - closestY)
    edge = clampUnit ((1 - sqrt (u * u + v * v)) * minorRadius contact)
    baseRadius sample = Kernel.baseRadius radius (samplePressure sample)
    minorRadius sample = Kernel.minorRadius radius (samplePressure sample) (sampleAltitude sample)
    majorRadius sample = Kernel.majorRadius radius (samplePressure sample) (sampleAltitude sample)
    local sample (offsetX, offsetY)
      | sampleAltitude sample == pi / 2 = (offsetX / baseRadius sample, offsetY / baseRadius sample)
      | otherwise =
          let angle = sampleAzimuth sample
              cosine = cos angle
              sine = sin angle
           in ( (cosine * offsetX + sine * offsetY) / majorRadius sample
              , (-sine * offsetX + cosine * offsetY) / minorRadius sample
              )
    project (offsetX, offsetY) (segmentX, segmentY)
      | lengthSquared == 0 = 1
      | otherwise = clampUnit ((offsetX * segmentX + offsetY * segmentY) / lengthSquared)
      where
        lengthSquared = segmentX * segmentX + segmentY * segmentY

clampUnit :: Double -> Double
clampUnit = max 0 . min 1

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

unit :: Double -> Bool
unit value = finite value && value >= 0 && value <= 1

finiteColor :: RGB -> Bool
finiteColor (RGB r g b) = all finite [r, g, b]
