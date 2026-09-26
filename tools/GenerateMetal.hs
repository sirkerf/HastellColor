module Main (main) where

import HastellColor.Brush.Kernel (metalFunctions)
import HastellColor.Brush.OilPastel (OilPastel (..), PastelState (..), drawStroke)
import HastellColor.Color (RGB (..), white)
import HastellColor.Paper (Paper (..), PaperSettings (..), PaperCell (..), makePaper)
import HastellColor.Stroke (Point (..), Stroke (..), StrokeSample (..), uprightSample)
import Control.Monad (foldM)
import Data.List (intercalate)
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
  args <- getArgs
  template <- readFile "metal/Paint.metal.in"
  let source = metalFunctions ++ "\n" ++ template
      path = "apple/HastellColor/Generated/Paint.metal"
  case args of
    [] -> writeFile path source
    ["--check"] -> do
      current <- readFile path
      if current == source then putStrLn "Metal source is up to date."
        else die "Metal source is stale. Run: cabal run hastellcolor-metal"
    ["--fixtures", output] -> either die (writeFile output) referenceFixtures
    _ -> die "Usage: cabal run hastellcolor-metal [-- --check | --fixtures PATH] (from repository root)"

-- GPU tests compare the complete pigment state, not just a screenshot. The
-- interactive brush has replenished supply and no wear, represented here by
-- fresh state and a capacity much larger than the small reference canvas.
referenceFixtures :: Either String String
referenceFixtures = do
  cases <- mapM encodeCase scenarios
  pure ("[" ++ intercalate "," cases ++ "]\n")
  where
    point x y p = uprightSample (Point x y) p
    tilted x y p a z = StrokeSample (Point x y) p a z
    redInk = RGB 0.85 0.045 0.018
    blueInk = RGB 0.035 0.07 0.65
    scenarios =
      [ ("upright", [(redInk, [point 4 12 0.6, point 28 12 0.6])])
      , ("split", [(redInk, [point x 12 0.6 | x <- [4, 8 .. 28]])])
      , ("weak", [(redInk, [point 4 12 0.2, point 28 12 0.2])])
      , ("tilted", [(redInk, [tilted 5 8 0.7 (pi/6) (pi/4), tilted 28 17 0.7 (pi/6) (pi/4)])])
      , ("varying", [(redInk, [tilted 3 4 0.2 (pi/2) 3.0, tilted 28 20 0.9 (pi/6) (-3.0)])])
      , ("edge", [(redInk, [point (-20) 0 0.9, point 12 0 0.9])])
      , ("dot", [(redInk, [point 16 12 0.8])])
      , ("zero", [(redInk, [point 16 12 0])])
      , ("outside", [(redInk, [point (-20) (-20) 0.9])])
      , ("layers", [(redInk, [point 4 12 0.8, point 28 12 0.8]),
                      (blueInk, [point 16 3 0.7, point 16 21 0.7])])
      ]
    encodeCase (name, strokes) = do
      blank <- makePaper (PaperSettings 32 24 white 0.9 42)
      final <- foldM (\paper (color, samples) -> fst <$> drawStroke
        (OilPastel color 4.5 1e30) (PastelState 1 0) (Stroke samples) paper) blank strokes
      let rgb (RGB r g b) = [r, g, b]
          sample s = let Point x y = samplePosition s
                     in [x, y, samplePressure s, sampleAltitude s, sampleAzimuth s]
          cell c = rgb (cellPigmentColor c) ++ [cellPigmentAmount c]
      pure ("{\"name\":" ++ show name ++ ",\"colors\":" ++ show (map (rgb . fst) strokes)
        ++ ",\"samples\":" ++ show (map (map sample . snd) strokes)
        ++ ",\"pixels\":" ++ show (concatMap cell (paperCells final)) ++ "}")
