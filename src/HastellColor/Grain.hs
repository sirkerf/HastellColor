-- | Presets describe tooth spacing in millimetres and depth separately.
-- These are tunable approximations, not measurements of a named paper.
module HastellColor.Grain
  ( Grain (..), grainSettings, grainHeight, makeGrainedPaper, grainMetalSettings
  ) where

import Data.Bits (shiftR, xor)
import Data.Word (Word32)
import HastellColor.Brush.Kernel (paperRelief)
import HastellColor.Paper (Paper (..), PaperCell (..), PaperSettings (..), makePaper)

data Grain = Legacy | Coarse | Medium | Fine deriving (Eq, Show, Enum, Bounded)

grainSettings :: Grain -> (Double, Double)
grainSettings Legacy = (25.4 / 300, 0.9)
grainSettings Coarse = (0.35, 0.95)
grainSettings Medium = (0.17, 0.7)
grainSettings Fine = (0.08, 0.45)

grainHeight :: Grain -> Double -> Word32 -> Int -> Int -> Double
grainHeight Legacy _ seed x y = paperRelief (noise seed x y) (noise seed (x `div` 4) (y `div` 4)) 0.9
grainHeight kind dpi seed x y = paperRelief (smooth u v) (smooth (u / 4) (v / 4)) depth
  where
    (spacing, depth) = grainSettings kind
    scale = spacing * dpi / 25.4
    u = (fromIntegral x + 0.5) / scale
    v = (fromIntegral y + 0.5) / scale
    smooth a b =
      let ix = floor a; iy = floor b
          ease t = t * t * (3 - 2 * t)
          tx = ease (a - fromIntegral ix); ty = ease (b - fromIntegral iy)
          mix t left right = left * (1 - t) + right * t
       in mix ty (mix tx (noise seed ix iy) (noise seed (ix + 1) iy))
                 (mix tx (noise seed ix (iy + 1)) (noise seed (ix + 1) (iy + 1)))

makeGrainedPaper :: Grain -> Double -> PaperSettings -> Either String Paper
makeGrainedPaper kind dpi settings
  | isNaN dpi || isInfinite dpi || dpi < 36 || dpi > 1200 = Left "Invalid paper resolution."
  | otherwise = do
      paper <- makePaper settings {paperRoughness = snd (grainSettings kind)}
      let width = paperWidth settings
      pure paper {paperCells = zipWith (\i cell -> cell
        {cellHeight = grainHeight kind dpi (paperSeed settings) (i `mod` width) (i `div` width)})
        [0..] (paperCells paper)}

noise :: Word32 -> Int -> Int -> Double
noise seed x y = fromIntegral third / 4294967295
  where
    value = seed + fromIntegral x * 374761393 + fromIntegral y * 668265263
    first = value `xor` (value `shiftR` 16)
    second = (first * 2146121005) `xor` ((first * 2146121005) `shiftR` 15)
    productValue = second * 2221713035
    third = productValue `xor` (productValue `shiftR` 16)

grainMetalSettings :: String
grainMetalSettings = unlines $
  ["float2 hcGrainSettings(uint kind, float dpi) {", "    switch (kind) {"]
  ++ ["    case " ++ show (fromEnum kind) ++ "u: return float2(" ++ show spacing
      ++ "f * dpi / 25.4f, " ++ show depth ++ "f);"
     | kind <- [Legacy .. Fine], let (spacing, depth) = grainSettings kind]
  ++ ["    default: return float2(1, 0.9f);", "    }", "}"]
