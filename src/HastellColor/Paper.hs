-- | Paper settings and deposited pigment, independent of image file formats.
module HastellColor.Paper
  ( PaperSettings (..)
  , PaperCell (..)
  , Paper (..)
  , makePaper
  , visibleColor
  , surfaceHeights
  ) where

import Data.Bits (shiftR, xor)
import Data.Word (Word32)
import HastellColor.Color (RGB (..), black, blendRGB, clampRGB)

-- | Dimensions are measured in cells and must be positive.
-- Roughness is normalized to [0, 1]; zero denotes smooth paper.
data PaperSettings = PaperSettings
  { paperWidth :: Int
  , paperHeight :: Int
  , paperBaseColor :: RGB
  , paperRoughness :: Double
  , paperSeed :: Word32
  }
  deriving (Eq, Show)

-- | Height and pigment amount are normalized to [0, 1].
-- Higher cells represent peaks in the paper grain.
-- When the amount is zero, pigment color does not affect the visible color.
data PaperCell = PaperCell
  { cellHeight :: Double
  , cellPigmentColor :: RGB
  , cellPigmentAmount :: Double
  }
  deriving (Eq, Show)

-- | Cells are stored row by row, from the top left.
-- The cell count must equal width * height in the settings.
data Paper = Paper
  { paperSettings :: PaperSettings
  , paperCells :: [PaperCell]
  }
  deriving (Eq, Show)

-- | Create deterministic paper grain without IO or a random package.
makePaper :: PaperSettings -> Either String Paper
makePaper settings
  | width <= 0 || height <= 0 = Left "Paper dimensions must be positive."
  | toInteger width * toInteger height > toInteger (maxBound :: Int) =
      Left "Paper dimensions are too large."
  | not (all finite [roughness, red base, green base, blue base]) =
      Left "Paper settings must contain finite numbers."
  | roughness < 0 || roughness > 1 = Left "Paper roughness must be in [0, 1]."
  | otherwise = Right Paper
      { paperSettings = settings {paperBaseColor = clampRGB base}
      , paperCells =
          [ PaperCell (1 - roughness * grain x y) black 0
          | y <- [0 .. height - 1]
          , x <- [0 .. width - 1]
          ]
      }
  where
    width = paperWidth settings
    height = paperHeight settings
    base = paperBaseColor settings
    roughness = paperRoughness settings
    -- Fine grain plus a small coarser component; both stay in [0, 1].
    grain x y = 0.8 * noise x y + 0.2 * noise (x `div` 4) (y `div` 4)
    noise x y = fromIntegral (hash coordinate) / 4294967295
      where
        coordinate = paperSeed settings + fromIntegral x * 374761393 + fromIntegral y * 668265263
    finite value = not (isNaN value || isInfinite value)

-- | Approximate the appearance of a cell over the paper's base color.
visibleColor :: PaperSettings -> PaperCell -> RGB
visibleColor settings cell =
  blendRGB (cellPigmentAmount cell) (paperBaseColor settings) (cellPigmentColor cell)

-- | A derived contact surface, in the same row-major order as the cells.
-- Own pigment raises the surface; surrounding pigment approximates bridging
-- over small valleys. This is a tunable coverage heuristic, not a thickness
-- simulation. It never changes paper grain or creates/transfers pigment.
-- The input must be valid rectangular paper. Outside neighbours contain no
-- pigment, and rows never wrap around at an edge.
surfaceHeights :: Paper -> [Double]
surfaceHeights paper
  | width <= 0 = []
  | otherwise = zipWith raisedHeight (paperCells paper) adjacentAmounts
  where
    width = paperWidth (paperSettings paper)
    rows = chunks width (map cellPigmentAmount (paperCells paper))
    zeroRow = replicate width 0
    previous = zeroRow : rows
    following = drop 1 rows ++ [zeroRow]
    adjacentAmounts = concat (zipWith3 neighbours previous rows following)
    neighbours above current below = zipWith3 mean
      (horizontal above) (horizontal current) (horizontal below)
      `subtractCenters` current
    horizontal row = zipWith3 (\a b c -> a + b + c)
      (0 : row) row (drop 1 row ++ [0])
    mean a b c = a + b + c
    subtractCenters totals centers = zipWith (\total center -> (total - center) / 8) totals centers
    raisedHeight cell nearby =
      let amount = cellPigmentAmount cell
          fill = max 0 (min 1 (0.65 * amount + 1.6 * nearby))
          height = cellHeight cell
       in height + (1 - height) * fill
    chunks _ [] = []
    chunks size values = let (row, rest) = splitAt size values in row : chunks size rest

-- Word32 arithmetic gives reproducible wraparound on all target platforms.
hash :: Word32 -> Word32
hash value = third `xor` (third `shiftR` 16)
  where
    first = value `xor` (value `shiftR` 16)
    second = (first * 2146121005) `xor` ((first * 2146121005) `shiftR` 15)
    third = second * 2221713035
