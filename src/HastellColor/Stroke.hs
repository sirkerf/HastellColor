-- | Stroke input in paper coordinates, independent of platform input APIs.
module HastellColor.Stroke
  ( Point (..)
  , StrokeSample (..)
  , Stroke (..)
  , uprightSample
  , interpolateSample
  ) where

-- | Coordinates in paper-cell units. X increases rightward, Y downward.
data Point = Point
  { pointX :: Double
  , pointY :: Double
  }
  deriving (Eq, Show)

-- | Pressure is in [0, 1]; zero means no pigment deposition.
-- Angles are in radians. Altitude is measured from the paper plane, from 0
-- (flat) to pi/2 (upright). Azimuth runs from +X towards +Y, clockwise on paper.
data StrokeSample = StrokeSample
  { samplePosition :: Point
  , samplePressure :: Double
  , sampleAltitude :: Double
  , sampleAzimuth :: Double
  }
  deriving (Eq, Show)

-- | A convenient upright input sample with no preferred azimuth.
uprightSample :: Point -> Double -> StrokeSample
uprightSample position pressure = StrokeSample position pressure (pi / 2) 0

-- | Interpolate validated samples, taking the shorter arc for azimuth.
-- The fraction is clamped to [0, 1] and must be finite.
interpolateSample :: Double -> StrokeSample -> StrokeSample -> StrokeSample
interpolateSample fraction start end
  | fraction <= 0 = start
  | fraction >= 1 = end
  | otherwise = StrokeSample
      { samplePosition = Point (mix ax bx) (mix ay by)
      , samplePressure = mix (samplePressure start) (samplePressure end)
      , sampleAltitude = mix (sampleAltitude start) (sampleAltitude end)
      , sampleAzimuth = startAngle + fraction * angleDelta
      }
  where
    Point ax ay = samplePosition start
    Point bx by = samplePosition end
    mix a b
      | a == b = a
      | otherwise = (1 - fraction) * a + fraction * b
    startAngle = atan2 (sin (sampleAzimuth start)) (cos (sampleAzimuth start))
    endAngle = atan2 (sin (sampleAzimuth end)) (cos (sampleAzimuth end))
    angleDelta = atan2 (sin (endAngle - startAngle)) (cos (endAngle - startAngle))

-- | Samples in drawing order. An empty stroke has no effect.
newtype Stroke = Stroke
  { strokeSamples :: [StrokeSample]
  }
  deriving (Eq, Show)
