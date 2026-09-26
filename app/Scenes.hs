-- | Reproducible example scenes. All drawing still lives in the core library.
module Scenes
  ( ComparisonCase (..)
  , ComparisonSample (..)
  , comparisonCases
  , renderComparisonCase
  , renderComparisons
  , singleStroke
  , settings
  , pastel
  ) where

import Control.Monad (foldM)
import HastellColor.Brush.OilPastel (OilPastel (..), PastelState (..), drawStroke)
import HastellColor.Color (RGB (..), white)
import HastellColor.Paper (Paper, PaperSettings (..), makePaper)
import HastellColor.Stroke (Point (..), Stroke (..), StrokeSample (..), uprightSample)

data ComparisonCase = ComparisonCase
  { caseLabel :: String
  , casePressure :: Double
  , caseRoughness :: Double
  , caseCoats :: Int
  , caseAltitude :: Double
  , caseAzimuth :: Double
  }
  deriving (Eq, Show)

data ComparisonSample = ComparisonSample
  { sampleCase :: ComparisonCase
  , samplePaper :: Paper
  , samplePastelState :: PastelState
  }
  deriving (Eq, Show)

-- Each row varies just one input. The medium-pressure, rough-paper, one-coat
-- baseline appears in all four rows to make cross-row comparison possible.
comparisonCases :: [(String, [ComparisonCase])]
comparisonCases =
  [ ("PRESSURE / ROUGHNESS 0.9 / 1 COAT",
      [ uprightCase "0.2 / LOW" 0.2 0.9 1
      , uprightCase "0.5 / MEDIUM" 0.5 0.9 1
      , uprightCase "0.9 / HIGH" 0.9 0.9 1
      ])
  , ("ROUGHNESS / PRESSURE 0.5 / 1 COAT",
      [ uprightCase "0.0 / SMOOTH" 0.5 0 1
      , uprightCase "0.5 / MEDIUM" 0.5 0.5 1
      , uprightCase "0.9 / ROUGH" 0.5 0.9 1
      ])
  , ("COATS / PRESSURE 0.5 / ROUGHNESS 0.9",
      [ uprightCase "1 COAT" 0.5 0.9 1
      , uprightCase "2 COATS" 0.5 0.9 2
      , uprightCase "10 COATS" 0.5 0.9 10
      ])
  , ("ALTITUDE / PRESSURE 0.5 / AZIMUTH 90 DEG",
      [ ComparisonCase "90 DEG / UPRIGHT" 0.5 0.9 1 (pi / 2) (pi / 2)
      , ComparisonCase "60 DEG" 0.5 0.9 1 (pi / 3) (pi / 2)
      , ComparisonCase "30 DEG" 0.5 0.9 1 (pi / 6) (pi / 2)
      ])
  ]
  where
    uprightCase label pressure roughness coats =
      ComparisonCase label pressure roughness coats (pi / 2) 0

renderComparisonCase :: ComparisonCase -> Either String ComparisonSample
renderComparisonCase spec
  | caseCoats spec <= 0 = Left "A comparison must use at least one coat."
  | otherwise = do
      paper <- makePaper settings {paperRoughness = caseRoughness spec}
      (painted, state) <- foldM paint (paper, freshPastel) [1 .. caseCoats spec]
      pure (ComparisonSample spec painted state)
  where
    path = Stroke
      [ sample {sampleAltitude = caseAltitude spec, sampleAzimuth = caseAzimuth spec}
      | sample <- strokeSamples (stroke (casePressure spec) (casePressure spec))
      ]
    paint (paper, state) _ = drawStroke pastel state path paper

renderComparisons :: Either String [(String, [ComparisonSample])]
renderComparisons = traverse renderRow comparisonCases
  where
    renderRow (title, cases) = do
      samples <- traverse renderComparisonCase cases
      pure (title, samples)

singleStroke :: Either String Paper
singleStroke = do
  paper <- makePaper settings
  fst <$> drawStroke pastel freshPastel (stroke 0.2 0.95) paper

settings :: PaperSettings
settings = PaperSettings
  { paperWidth = 256
  , paperHeight = 256
  , paperBaseColor = white
  , paperRoughness = 0.9
  , paperSeed = 42
  }

pastel :: OilPastel
pastel = OilPastel
  { pastelColor = RGB 0.82 0.18 0.08
  , pastelRadius = 14
  , pastelCapacity = 20000
  }

freshPastel :: PastelState
freshPastel = PastelState 1 0

stroke :: Double -> Double -> Stroke
stroke startPressure endPressure = Stroke
  [ uprightSample (Point 50 100) startPressure
  , uprightSample (Point 200 140) endPressure
  ]
