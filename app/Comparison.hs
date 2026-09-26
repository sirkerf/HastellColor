-- | Presentation of the reference scenes; no drawing physics belongs here.
module Comparison (comparisonPPM) where

import Data.Bits (testBit)
import Data.Char (toUpper)
import Data.List (intersperse, transpose)
import HastellColor.Brush.OilPastel (OilPastel (..))
import HastellColor.Color (RGB (..), white)
import HastellColor.Image.PPM (encodeRGBRows)
import HastellColor.Paper (Paper (..), PaperSettings (..), visibleColor)
import Scenes (ComparisonCase (..), ComparisonSample (..), pastel, renderComparisons)
import qualified Scenes

comparisonPPM :: Either String String
comparisonPPM = do
  samples <- renderComparisons
  encodeRGBRows (sheet samples)

-- Every paper is shown at native resolution; labels live outside the paper.
sheet :: [(String, [ComparisonSample])] -> [[RGB]]
sheet rows =
  band 20
    ++ heading 3 "HASTELLCOLOR / OIL PASTEL"
    ++ band 10
    ++ heading 2 ("SEED " ++ show (paperSeed Scenes.settings)
      ++ " / RADIUS " ++ show (pastelRadius pastel)
      ++ " / PAPER " ++ show (paperWidth Scenes.settings) ++ " X " ++ show (paperHeight Scenes.settings))
    ++ band 10
    ++ heading 1 "BASE ALTITUDE 90 DEG. ALTITUDE IS MEASURED FROM THE PAPER."
    ++ band 14
    ++ concatMap section rows
    ++ heading 1 "EACH PANEL STARTS FRESH. COATS CARRY PIGMENT LOAD AND WEAR."
    ++ band 16
  where
    width = 832
    band height = replicate height (replicate width background)
    heading scale text = map (pad 16 background width) (textRows scale ink background text)
    section (title, samples) =
      heading 2 title ++ band 10
        ++ map (pad 16 background width) (beside 16 background (map card samples))
        ++ band 24

card :: ComparisonSample -> [[RGB]]
card sample =
  replicate 10 blank
    ++ map (pad 12 white width) (textRows 2 ink white (caseLabel (sampleCase sample)))
    ++ replicate 8 blank
    ++ paperRows
  where
    paper = samplePaper sample
    settings = paperSettings paper
    width = paperWidth settings
    blank = replicate width white
    paperRows = chunks width (map (visibleColor settings) (paperCells paper))

beside :: Int -> RGB -> [[[RGB]]] -> [[RGB]]
beside gap color = map (concat . intersperse (replicate gap color)) . transpose

pad :: Int -> RGB -> Int -> [RGB] -> [RGB]
pad left color width pixels = take width (replicate left color ++ pixels ++ repeat color)

chunks :: Int -> [a] -> [[a]]
chunks _ [] = []
chunks size values = let (row, rest) = splitAt size values in row : chunks size rest

background, ink :: RGB
background = RGB 0.94 0.95 0.96
ink = RGB 0.15 0.18 0.22

-- A small built-in 5x7 font keeps PPM labels dependency-free.
textRows :: Int -> RGB -> RGB -> String -> [[RGB]]
textRows scale foreground backdrop text = concatMap (replicate scale)
  [ concatMap (concatMap (replicate scale) . glyphRow row) text
  | row <- [0 .. 6]
  ]
  where
    glyphRow row character =
      [if testBit (glyph (toUpper character) !! row) column then foreground else backdrop
      | column <- [4, 3 .. 0]] ++ [backdrop]

glyph :: Char -> [Int]
glyph character = case character of
  'A' -> [14,17,17,31,17,17,17]
  'B' -> [30,17,17,30,17,17,30]
  'C' -> [14,17,16,16,16,17,14]
  'D' -> [30,17,17,17,17,17,30]
  'E' -> [31,16,16,30,16,16,31]
  'F' -> [31,16,16,30,16,16,16]
  'G' -> [14,17,16,23,17,17,15]
  'H' -> [17,17,17,31,17,17,17]
  'I' -> [14,4,4,4,4,4,14]
  'J' -> [7,2,2,2,18,18,12]
  'K' -> [17,18,20,24,20,18,17]
  'L' -> [16,16,16,16,16,16,31]
  'M' -> [17,27,21,21,17,17,17]
  'N' -> [17,25,21,19,17,17,17]
  'O' -> [14,17,17,17,17,17,14]
  'P' -> [30,17,17,30,16,16,16]
  'Q' -> [14,17,17,17,21,18,13]
  'R' -> [30,17,17,30,20,18,17]
  'S' -> [15,16,16,14,1,1,30]
  'T' -> [31,4,4,4,4,4,4]
  'U' -> [17,17,17,17,17,17,14]
  'V' -> [17,17,17,17,17,10,4]
  'W' -> [17,17,17,21,21,21,10]
  'X' -> [17,17,10,4,10,17,17]
  'Y' -> [17,17,10,4,4,4,4]
  'Z' -> [31,1,2,4,8,16,31]
  '0' -> [14,17,19,21,25,17,14]
  '1' -> [4,12,4,4,4,4,14]
  '2' -> [14,17,1,2,4,8,31]
  '3' -> [30,1,1,14,1,1,30]
  '4' -> [2,6,10,18,31,2,2]
  '5' -> [31,16,16,30,1,1,30]
  '6' -> [14,16,16,30,17,17,14]
  '7' -> [31,1,2,4,8,8,8]
  '8' -> [14,17,17,14,17,17,14]
  '9' -> [14,17,17,15,1,1,14]
  '/' -> [1,1,2,4,8,16,16]
  '.' -> [0,0,0,0,0,6,6]
  _ -> replicate 7 0
