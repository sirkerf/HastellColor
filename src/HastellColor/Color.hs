module HastellColor.Color
  ( RGB(..)
  , black
  , white
  , clampRGB
  , blendRGB
  ) where

data RGB = RGB
  { red   :: Double
  , green :: Double
  , blue  :: Double
  }
  deriving (Eq, Show)

black :: RGB
black = RGB 0 0 0

white :: RGB
white = RGB 1 1 1

clampRGB :: RGB -> RGB
clampRGB (RGB r g b) =
  RGB (clamp r) (clamp g) (clamp b)
  where
    clamp x = max 0 (min 1 x)

-- | Interpolate RGB components: 0 gives the background, 1 the foreground.
-- This is a display approximation, not a physical pigment mixing model.
-- Inputs are expected to be finite; the result is clamped to [0, 1].
blendRGB :: Double -> RGB -> RGB -> RGB
blendRGB amount background foreground =
  clampRGB (RGB (mix red) (mix green) (mix blue))
  where
    weight = max 0 (min 1 amount)
    mix component =
      (1 - weight) * component background + weight * component foreground
