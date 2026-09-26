module Main (main) where

import Comparison (comparisonPPM)
import HastellColor.Image.PPM (encodePPM)
import Scenes (singleStroke)
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> save "hastellcolor.ppm" (encodePPM <$> singleStroke)
    ["--comparison"] -> save "hastellcolor-comparison.ppm" comparisonPPM
    ["--comparison", path] -> save path comparisonPPM
    ["--help"] -> putStrLn usage
    [path] -> save path (encodePPM <$> singleStroke)
    _ -> die usage

save :: FilePath -> Either String String -> IO ()
save outputPath result = do
  ppm <- either die pure result
  writeFile outputPath ppm
  putStrLn ("Wrote " ++ outputPath)

usage :: String
usage = unlines
  [ "Usage: cabal run HastellColor -- [output.ppm]"
  , "       cabal run HastellColor -- --comparison [output.ppm]"
  ]
