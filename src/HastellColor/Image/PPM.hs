-- | Plain-text PPM (P3) encoding. Saving the result is the caller's job.
module HastellColor.Image.PPM (encodePPM, encodeRGBRows) where

import HastellColor.Color (RGB (..), clampRGB)
import HastellColor.Paper
  ( Paper (..), PaperSettings (..), visibleColor )

-- | Encode valid paper in row-major order with 8-bit RGB components.
encodePPM :: Paper -> String
encodePPM paper = encodePixels (paperWidth settings) (paperHeight settings)
  (map (visibleColor settings) (paperCells paper))
  where
    settings = paperSettings paper

-- | Encode a rectangular RGB image, such as a sheet assembled from papers.
-- Reject empty/ragged images and non-finite components; clamp finite colors.
encodeRGBRows :: [[RGB]] -> Either String String
encodeRGBRows [] = Left "An image must contain at least one row."
encodeRGBRows rows@(first : _)
  | null first = Left "Image rows must contain at least one pixel."
  | any ((/= width) . length) rows = Left "Image rows must have the same width."
  | not (all finiteColor (concat rows)) = Left "Image colors must be finite."
  | otherwise = Right (encodePixels width (length rows) (concat rows))
  where
    width = length first
    finiteColor (RGB r g b) = all (\value -> not (isNaN value || isInfinite value)) [r, g, b]

encodePixels :: Int -> Int -> [RGB] -> String
encodePixels width height colors = unlines
  (["P3", show width ++ " " ++ show height, "255"] ++ map pixel colors)
  where
    pixel color =
      let RGB r g b = clampRGB color
       in unwords (map (show . toByte) [r, g, b])
    toByte :: Double -> Int
    toByte value = round (255 * value)
