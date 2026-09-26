-- | A conservative reference step: directed transport into unfilled paper,
-- plus symmetric pigment exchange that can mix two fully covered colours.
module HastellColor.Brush.Rubbing
  ( RubTool (..), rubSettings, rubStep, rubMetalSettings
  ) where

import qualified HastellColor.Brush.Kernel as K
import HastellColor.Color (RGB (..))
import HastellColor.Paper (Paper (..), PaperCell (..), PaperSettings (..), surfaceHeights)
import HastellColor.Stroke (StrokeSample (..), Point (..))

data RubTool = Finger | Stump | Silicone | Kneaded deriving (Eq, Show, Enum, Bounded)

-- Footprint scale, edge softness, directed transport, symmetric exchange.
rubSettings :: RubTool -> (Double, Double, Double, Double)
rubSettings Finger = (1.3, 0.65, 0.42, 0.22)
rubSettings Stump = (0.55, 0.3, 0.65, 0.10)
rubSettings Silicone = (1, 0.15, 0.82, 0.03)
rubSettings Kneaded = (1.1, 0.8, 0, 0)

rubStep :: RubTool -> Double -> Double -> StrokeSample -> (Double, Double) -> Paper -> Either String Paper
rubStep tool radius strength sample (dx, dy) paper
  | width <= 0 || height <= 0 || toInteger width * toInteger height /= toInteger (length cells) = Left "Invalid paper."
  | not (all finite [radius, strength, cx, cy, pressure, altitude, azimuth, dx, dy])
      || radius <= 0 || strength < 0.25 || strength > 2.5 || pressure < 0 || pressure > 1
      || altitude < 0 || altitude > pi / 2 = Left "Invalid rubbing input."
  | otherwise = Right paper {paperCells = [update x y | y <- [0..height-1], x <- [0..width-1]]}
  where
    settings = paperSettings paper
    width = paperWidth settings; height = paperHeight settings
    cells = paperCells paper; surfaces = surfaceHeights paper
    Point cx cy = samplePosition sample
    pressure = samplePressure sample; altitude = sampleAltitude sample; azimuth = sampleAzimuth sample
    (scale, softness, mobility, mixing) = rubSettings tool
    at x y = cells !! (y * width + x)
    inside x y = x >= 0 && y >= 0 && x < width && y < height
    edge x y =
      let ox = fromIntegral x + 0.5 - cx; oy = fromIntegral y + 0.5 - cy
          rr = radius * scale
          (u, v) = if tool == Finger || tool == Kneaded then (ox / rr, oy / rr)
            else ((cos azimuth * ox + sin azimuth * oy) / K.majorRadius rr pressure altitude,
                  (-sin azimuth * ox + cos azimuth * oy) / K.minorRadius rr pressure altitude)
       in max 0 (min 1 ((1 - sqrt (u*u + v*v)) / softness))
    weight x y = K.rubContact (surfaces !! (y*width+x)) pressure (edge x y) strength
    totalDirection = abs dx + abs dy
    axes = if totalDirection == 0 then [] else
      [(round (signum dx), 0, abs dx / totalDirection),
       (0, round (signum dy), abs dy / totalDirection)]
    update x y
      | tool == Kneaded = cell {cellPigmentAmount = amount * (1 - K.liftingContact
          (surfaces !! (y*width+x)) pressure (edge x y) strength)}
      | otherwise =
          let changes = concat [flows ax ay portion | (ax,ay,portion) <- axes, portion > 0]
              incoming = sum [n | (_,n) <- changes]
              -- Signed fluxes carry the donor's colour. Sum in premultiplied form.
              resultAmount = amount + incoming
              resultColor channel = if resultAmount <= 0 then channel (cellPigmentColor cell)
                else (amount * channel (cellPigmentColor cell)
                   + sum [n * channel color | (color,n) <- changes]) / resultAmount
           in cell {cellPigmentAmount = resultAmount,
                cellPigmentColor = RGB (resultColor red) (resultColor green) (resultColor blue)}
      where
        cell = at x y; amount = cellPigmentAmount cell
        flows ax ay portion = concatMap (pair portion) [(x+ax,y+ay,True),(x-ax,y-ay,False)]
        pair portion (qx,qy,forward)
          | not (inside qx qy) = []
          | otherwise =
              let other = at qx qy; b = cellPigmentAmount other
                  w = weight x y; v = weight qx qy
                  exchange = portion * K.pigmentExchange amount b (min w v) mixing
                  transfer = if forward then portion * K.pigmentTransfer amount b w mobility
                             else portion * K.pigmentTransfer b amount v mobility
                  ownColor = cellPigmentColor cell; otherColor = cellPigmentColor other
               in [(ownColor,-exchange),(otherColor,exchange)]
                  ++ if forward then [(ownColor,-transfer)] else [(otherColor,transfer)]
    finite a = not (isNaN a || isInfinite a)

rubMetalSettings :: String
rubMetalSettings = unlines $
  ["float4 hcRubSettings(uint kind) {", "    switch (kind) {"]
  ++ ["    case " ++ show (fromEnum tool + 1) ++ "u: return float4(" ++ show a ++ "f, " ++ show b
      ++ "f, " ++ show c ++ "f, " ++ show d ++ "f);"
     | tool <- [Finger .. Kneaded], let (a,b,c,d) = rubSettings tool]
  ++ ["    default: return float4(1, 1, 0, 0);", "    }", "}"]
