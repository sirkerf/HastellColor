module Main (main) where

import Control.Monad (unless, foldM)
import Data.Either (isLeft)
import Data.List (transpose)
import HastellColor.Brush.OilPastel (OilPastel (..), PastelState (..), drawStroke)
import HastellColor.Color (RGB (..), black, blendRGB, clampRGB, white)
import HastellColor.Image.PPM (encodePPM, encodeRGBRows)
import HastellColor.Paper (Paper (..), PaperCell (..), PaperSettings (..), makePaper, visibleColor, surfaceHeights)
import HastellColor.Stroke (Point (..), Stroke (..), StrokeSample (..), uprightSample, interpolateSample)
import qualified HastellColor.Brush.Kernel as Kernel
import qualified HastellColor.Grain as Grain
import qualified HastellColor.Brush.Rubbing as Rub
import qualified Scenes
import System.Exit (die, exitFailure)

main :: IO ()
main = do
  paper <- either die pure (makePaper settings)
  smooth <- either die pure (makePaper settings {paperRoughness = 0})
  otherSeed <- either die pure (makePaper settings {paperSeed = 7})
  low <- render pastel fresh (line 0.2) paper
  high <- render pastel fresh (line 0.9) paper
  twice <- render pastel (snd high) (line 0.9) (fst high)
  blueCoat <- render pastel {pastelColor = RGB 0 0 1} fresh (line 0.9) (fst high)
  scarce <- render pastel {pastelCapacity = 0.5} (PastelState 0.2 0.8) (line 0.9) paper
  split <- render pastel fresh splitLine paper
  whole <- render pastel fresh (line 0.6) paper
  dot <- render pastel fresh (Stroke [sample 16 12 0.6]) paper
  duplicate <- render pastel fresh (Stroke [sample 16 12 0.6, sample 16 12 0.6]) paper
  clipped <- render pastel fresh (Stroke [sample (-20) 12 0.8, sample 20 12 0.8]) paper
  weakGrain <- render pastel fresh (Stroke [sample 1 0.5 0.2]) peaksAndValleys
  strongGrain <- render pastel fresh (Stroke [sample 1 0.5 1]) peaksAndValleys
  square <- either die pure (makePaper (PaperSettings 41 41 white 0 42))
  uprightDot <- render pastel fresh (Stroke [sample 20.5 20.5 0.8]) square
  uprightTurned <- render pastel fresh (Stroke [(sample 20.5 20.5 0.8) {sampleAzimuth = 2.3}]) square
  tiltedDot <- render pastel fresh (Stroke [oriented 20.5 20.5 0.8 (pi / 6) 0]) square
  turnedDot <- render pastel fresh (Stroke [oriented 20.5 20.5 0.8 (pi / 6) (pi / 2)]) square
  fullTurn <- render pastel fresh (Stroke [oriented 20.5 20.5 0.8 (pi / 6) (2 * pi)]) square
  flatDot <- render pastel fresh (Stroke [oriented 20.5 20.5 0.8 0 0]) square
  tiltedWhole <- render pastel fresh (orientStroke (pi / 6) (pi / 4) (line 0.6)) paper
  tiltedSplit <- render pastel fresh (orientStroke (pi / 6) (pi / 4) splitLine) paper
  varyingTilt <- render pastel fresh
    (Stroke [oriented 4 12 0.2 (pi / 2) 0, oriented 28 12 0.9 (pi / 6) (pi / 2)]) paper
  bareValley <- render pastel fresh (Stroke [sample 1.5 1.5 0.2]) valleyPaper
  bridgedValley <- render pastel fresh (Stroke [sample 1.5 1.5 0.2]) bridgedPaper
  comparisons <- either die pure Scenes.renderComparisons
  grained <- mapM (either die pure . (\g -> Grain.makeGrainedPaper g 300 settings)) [Grain.Coarse, Grain.Medium, Grain.Fine]
  layeredGrain <- mapM (\p -> do
    first <- render pastel fresh (line 0.6) p
    second <- render pastel fresh (line 0.6) (fst first)
    pure (p, fst first, fst second)) grained
  rubbed <- mapM (\tool -> either die pure (foldM
    (\p x -> Rub.rubStep tool 8 1 (sample x 12 0.8) (1,0) p) (fst blueCoat) [6..24]))
    [Rub.Finger, Rub.Stump, Rub.Silicone]
  lifted <- either die pure (Rub.rubStep Rub.Kneaded 8 1 (sample 16 12 0.8) (0,0) (fst blueCoat))
  let componentMass channel = sum . map (\c -> cellPigmentAmount c * channel (cellPigmentColor c)) . paperCells
      checks =
        [ ("paper presets have distinct bounded grain",
            all (\p -> all (\c -> cellHeight c >= 0 && cellHeight c <= 1) (paperCells p)) grained
            && and (zipWith (/=) grained (drop 1 grained)))
        , ("legacy grain preserves old paper", Grain.makeGrainedPaper Grain.Legacy 300 settings == Right paper)
        , ("every grain accumulates pigment and raises its contact surface",
            all (\(blank,first,second) -> pigment second > pigment first && pigment first > 0
              && sum (surfaceHeights second) > sum (surfaceHeights blank)) layeredGrain)
        , ("rubbing conserves pigment", all (near (pigment (fst blueCoat)) . pigment) rubbed)
        , ("rubbing conserves pigment colour mass",
            and [near (componentMass channel p) (componentMass channel (fst blueCoat)) | p <- rubbed, channel <- [red,green,blue]])
        , ("rubbing keeps paper geometry and bounded pigment", all (\p -> validPigment p
            && map cellHeight (paperCells p) == map cellHeight (paperCells (fst blueCoat))) rubbed)
        , ("rubbing tools have distinct effects", and (zipWith (/=) rubbed (drop 1 rubbed)))
        , ("kneaded eraser lifts pigment", pigment lifted < pigment (fst blueCoat) && validPigment lifted)
        , ("rubbing blank paper never creates pigment", all (\tool -> Rub.rubStep tool 8 1 (sample 16 12 0.8) (1,0) paper == Right paper)
            [Rub.Finger, Rub.Stump, Rub.Silicone, Rub.Kneaded])
        , ("zero-pressure rubbing does nothing", all (\tool -> fmap (nearPaper (fst blueCoat))
            (Rub.rubStep tool 8 1 (sample 16 12 0) (1,0) (fst blueCoat)) == Right True)
            [Rub.Finger, Rub.Stump, Rub.Silicone, Rub.Kneaded])
        , ("stroke strength preserves zero contact and identity",
            all (\c -> Kernel.strokeContact c 1 == c && Kernel.strokeContact 0 c == (0 :: Double)) [0, 0.1, 0.5, 1])
        , ("stroke strength is monotone and bounded",
            all (\c -> let weak = Kernel.strokeContact c 0.25; strong = Kernel.strokeContact c 2.5
                       in weak >= 0 && weak <= strong && strong <= (1 :: Double)) [0, 0.1, 0.5, 1])
        , ("clampRGB preserves colors within [0, 1]", all (\color -> clampRGB color == color) inRangeColors)
        , ("clampRGB clips out-of-range components", clampRGB (RGB (-0.25) 0.5 1.25) == RGB 0 0.5 1)
        , ("clampRGB bounds every component", all (isInRange . clampRGB) sampleColors)
        , ("clampRGB is idempotent", all (\color -> clampRGB (clampRGB color) == clampRGB color) sampleColors)
        , ("blendRGB has clamped endpoints", blendRGB (-1) black white == black && blendRGB 2 black white == white)
        , ("blendRGB interpolates colors", blendRGB 0.25 black white == RGB 0.25 0.25 0.25)
        , ("paper has the requested dimensions", length (paperCells paper) == 32 * 24)
        , ("paper generation is reproducible", makePaper settings == Right paper && paper /= otherSeed)
        , ("blank paper shows its base color", all ((== white) . visibleColor settings) (paperCells paper))
        , ("grain height is bounded", all (\cell -> cellHeight cell >= 0 && cellHeight cell <= 1) (paperCells paper))
        , ("smooth paper has no height variation", all ((== 1) . cellHeight) (paperCells smooth))
        , ("invalid paper settings are rejected", all (isLeft . makePaper)
            [ settings {paperWidth = 0}, settings {paperHeight = -1}
            , settings {paperRoughness = 2}, settings {paperRoughness = 0 / 0}
            ])
        , ("empty stroke is unchanged", drawStroke pastel fresh (Stroke []) paper == Right (paper, fresh))
        , ("zero pressure is unchanged", drawStroke pastel fresh (line 0) paper == Right (paper, fresh))
        , ("empty pastel is unchanged", drawStroke pastel (PastelState 0 0) (line 1) paper == Right (paper, PastelState 0 0))
        , ("off-paper stroke is unchanged", drawStroke pastel fresh
            (Stroke [sample (-50) (-50) 1, sample (-30) (-30) 1]) paper == Right (paper, fresh))
        , ("higher pressure deposits more pigment", pigment (fst high) > pigment (fst low) && pigment (fst low) > 0)
        , ("higher pressure reaches more cells", paintedCount (fst high) > paintedCount (fst low))
        , ("weak pressure deposits on peaks", case paperCells (fst weakGrain) of
            [peak, valley] -> cellPigmentAmount peak > 0 && cellPigmentAmount valley == 0
            _ -> False)
        , ("strong pressure reaches valleys", all ((> 0) . cellPigmentAmount) (paperCells (fst strongGrain)))
        , ("drawing preserves paper geometry", paperSettings (fst high) == settings
            && map cellHeight (paperCells (fst high)) == map cellHeight (paperCells paper))
        , ("second coat accumulates pigment", pigment (fst twice) > pigment (fst high)
            && all (\cell -> cellPigmentAmount cell <= 1) (paperCells (fst twice)))
        , ("different colors mix on the paper", any (\cell -> cellPigmentAmount cell > 0
            && red (cellPigmentColor cell) > 0 && blue (cellPigmentColor cell) > 0) (paperCells (fst blueCoat)))
        , ("drawing consumes pigment and increases wear", pastelPigmentLoad (snd high) < 1
            && pastelWear (snd high) > 0
            && near (pigment (fst high)) ((1 - pastelPigmentLoad (snd high)) * pastelCapacity pastel))
        , ("limited pigment supply is conserved", near (pigment (fst scarce)) 0.1
            && near (pastelPigmentLoad (snd scarce)) 0 && near (pastelWear (snd scarce)) 1)
        , ("splitting a straight segment preserves deposition", nearPaper (fst whole) (fst split))
        , ("single and duplicate samples produce a dot", pigment (fst dot) > 0 && dot == duplicate)
        , ("a crossing stroke clips to the paper", paintedCount (fst clipped) > 0 && length (paperCells (fst clipped)) == 32 * 24)
        , ("invalid brush and stroke inputs are rejected", all isLeft
            [ drawStroke pastel {pastelRadius = 0} fresh (line 1) paper
            , drawStroke pastel {pastelCapacity = -1} fresh (line 1) paper
            , drawStroke pastel fresh (line (0 / 0)) paper
            , drawStroke pastel fresh (Stroke [sample (1 / 0) 0 1]) paper
            , drawStroke pastel fresh (line 1) paper {paperCells = []}
            ])
        , ("PPM header and RGB sample count are correct", validPPM (fst high))
        , ("PPM preserves cell and channel order", encodePPM
            (Paper (PaperSettings 2 1 white 0 0) [PaperCell 1 (RGB 1 0 0) 1, PaperCell 1 (RGB 0 0 1) 1])
            == "P3\n2 1\n255\n255 0 0\n0 0 255\n")
        , ("RGB image encoding preserves row and channel order", encodeRGBRows
            [[RGB 1 0 0, RGB 0 0 1], [white, black]]
            == Right "P3\n2 2\n255\n255 0 0\n0 0 255\n255 255 255\n0 0 0\n")
        , ("RGB image encoding rejects invalid images", all (isLeft . encodeRGBRows)
            [[], [[]], [[white], [white, black]], [[RGB (0 / 0) 0 0]]])
        , ("blank paper has no pigment-induced surface change", surfaceHeights paper == map cellHeight (paperCells paper))
        , ("own pigment raises the contact surface", surfaceHeights ownPigmentPaper !! 4 > 0)
        , ("neighbouring pigment raises an empty valley", surfaceHeights bridgedPaper !! 4 > surfaceHeights valleyPaper !! 4)
        , ("surface computation does not wrap across rows", surfaceHeights edgePigmentPaper !! 3 == 0
            && surfaceHeights edgePigmentPaper !! 5 > 0)
        , ("contact surface is bounded and never below paper", and (zipWith
            (\base raised -> raised >= base && raised <= 1) (map cellHeight (paperCells (fst high))) (surfaceHeights (fst high))))
        , ("bridging allows a previously untouched valley to receive pigment",
            cellPigmentAmount (paperCells (fst bareValley) !! 4) == 0
              && cellPigmentAmount (paperCells (fst bridgedValley) !! 4) > 0)
        , ("surface feedback still conserves newly deposited pigment",
            near (pigment (fst bridgedValley) - pigment bridgedPaper)
              ((1 - pastelPigmentLoad (snd bridgedValley)) * pastelCapacity pastel))
        , ("strong pressure retains grain inside the stroke",
            let amounts = map cellPigmentAmount (take 20 (drop (12 * 32 + 6) (paperCells (fst high))))
             in maximum amounts - minimum amounts > 0.05)
        , ("upright contact ignores azimuth", uprightDot == uprightTurned)
        , ("tilt broadens the contact footprint", paintedCount (fst tiltedDot) > paintedCount (fst uprightDot))
        , ("azimuth rotates the footprint", nearPaper (transposePaper (fst tiltedDot)) (fst turnedDot))
        , ("azimuth is periodic", nearPaper (fst tiltedDot) (fst fullTurn))
        , ("flat contact stays finite and bounded", validPigment (fst flatDot)
            && paintedCount (fst flatDot) >= paintedCount (fst tiltedDot))
        , ("tilted deposition conserves pigment", near (pigment (fst tiltedDot))
            ((1 - pastelPigmentLoad (snd tiltedDot)) * pastelCapacity pastel))
        , ("splitting a tilted segment preserves deposition", nearPaper (fst tiltedWhole) (fst tiltedSplit))
        , ("varying tilt produces finite deposition", validPigment (fst varyingTilt) && pigment (fst varyingTilt) > 0)
        , ("tilted zero-pressure input has no effect", drawStroke pastel fresh
            (orientStroke (pi / 6) (pi / 4) (line 0)) paper == Right (paper, fresh))
        , ("angle interpolation takes the short arc", interpolationChecks)
        , ("invalid orientation inputs are rejected", all (\point -> isLeft (drawStroke pastel fresh (Stroke [point]) paper))
            [ oriented 16 12 0.5 (-0.1) 0, oriented 16 12 0.5 pi 0
            , oriented 16 12 0.5 (0 / 0) 0, oriented 16 12 0.5 (pi / 4) (1 / 0)
            ])
        ] ++ comparisonChecks comparisons
      failures = [name | (name, passed) <- checks, not passed]
  mapM_ (putStrLn . ("FAIL: " ++)) failures
  unless (null failures) exitFailure
  putStrLn ("Passed " ++ show (length checks) ++ " checks.")

comparisonChecks :: [(String, [Scenes.ComparisonSample])] -> [(String, Bool)]
comparisonChecks rows = case map snd rows of
  [ [low, middle, high], [smooth, medium, rough], [once, twice, ten], [upright, tilted60, tilted30] ] ->
    [ ("comparison baseline is identical across all four rows",
        paper middle == paper rough && paper rough == paper once
          && paper once == paper upright
          && state middle == state rough && state rough == state once && state once == state upright)
    , ("comparison pressure increases deposition", increasing (map (pigment . paper) [low, middle, high]))
    , ("comparison roughness reduces deposition", increasing (map (pigment . paper) [rough, medium, smooth]))
    , ("comparison coats accumulate deposition", increasing (map (pigment . paper) [once, twice, ten]))
    , ("comparison coats progressively fill more cells", increasing (map (paintedCount . paper) [once, twice, ten]))
    , ("comparison tilt broadens coverage", increasing (map (paintedCount . paper) [upright, tilted60, tilted30]))
    , ("comparison coats carry pigment supply and wear",
        increasing (map (pastelWear . state) [once, twice, ten])
          && increasing (map (pastelPigmentLoad . state) [ten, twice, once]))
    , ("comparison uses identical grain for the same roughness", all
        ((== map cellHeight (paperCells (paper once))) . map cellHeight . paperCells . paper)
        [low, middle, high, rough, twice, ten, upright, tilted60, tilted30])
    , ("comparison panels use the same dimensions and seed", all
        (\panel -> let canvas = paper panel; config = paperSettings canvas
          in paperWidth config == 256 && paperHeight config == 256
            && paperSeed config == 42 && length (paperCells canvas) == 256 * 256)
        (concatMap snd rows))
    , ("comparison rejects nonpositive coat counts", all
        (isLeft . Scenes.renderComparisonCase)
        [ (Scenes.sampleCase once) {Scenes.caseCoats = 0}
        , (Scenes.sampleCase once) {Scenes.caseCoats = -1}
        ])
    ]
  _ -> [("comparison has four rows of three samples", False)]
  where
    paper = Scenes.samplePaper
    state = Scenes.samplePastelState
    increasing values = and (zipWith (<) values (drop 1 values))

settings :: PaperSettings
settings = PaperSettings 32 24 white 0.9 42

pastel :: OilPastel
pastel = OilPastel (RGB 1 0 0) 4 20000

fresh :: PastelState
fresh = PastelState 1 0

sample :: Double -> Double -> Double -> StrokeSample
sample x y pressure = uprightSample (Point x y) pressure

oriented :: Double -> Double -> Double -> Double -> Double -> StrokeSample
oriented x y pressure altitude azimuth = StrokeSample (Point x y) pressure altitude azimuth

orientStroke :: Double -> Double -> Stroke -> Stroke
orientStroke altitude azimuth (Stroke points) = Stroke
  [point {sampleAltitude = altitude, sampleAzimuth = azimuth} | point <- points]

valleyPaper :: Paper
valleyPaper = Paper (PaperSettings 3 3 white 1 42) (replicate 9 (PaperCell 0 black 0))

bridgedPaper :: Paper
bridgedPaper = valleyPaper {paperCells =
  [PaperCell 0 black (if index == (4 :: Int) then 0 else 1) | index <- [0 .. 8]]}

ownPigmentPaper :: Paper
ownPigmentPaper = valleyPaper {paperCells =
  [PaperCell 0 black (if index == (4 :: Int) then 0.5 else 0) | index <- [0 .. 8]]}

edgePigmentPaper :: Paper
edgePigmentPaper = valleyPaper {paperCells =
  [PaperCell 0 black (if index == (2 :: Int) then 1 else 0) | index <- [0 .. 8]]}

transposePaper :: Paper -> Paper
transposePaper paper = paper
  { paperSettings = config {paperWidth = paperHeight config, paperHeight = paperWidth config}
  , paperCells = concat (transpose (chunks (paperWidth config) (paperCells paper)))
  }
  where
    config = paperSettings paper
    chunks _ [] = []
    chunks width values = let (row, rest) = splitAt width values in row : chunks width rest

validPigment :: Paper -> Bool
validPigment = all (\cell -> let amount = cellPigmentAmount cell
  in not (isNaN amount || isInfinite amount) && amount >= 0 && amount <= 1
    && isInRange (cellPigmentColor cell)) . paperCells

interpolationChecks :: Bool
interpolationChecks =
  near (pointX (samplePosition middle)) 5
    && near (samplePressure middle) 0.5
    && near (sampleAltitude middle) (pi / 4)
    && near (cos (sampleAzimuth middle)) 1 && near (sin (sampleAzimuth middle)) 0
    && interpolateSample (-1) start end == start && interpolateSample 2 start end == end
  where
    start = oriented 0 0 0.2 (pi / 6) (350 * pi / 180)
    end = oriented 10 0 0.8 (pi / 3) (10 * pi / 180)
    middle = interpolateSample 0.5 start end

line :: Double -> Stroke
line pressure = Stroke [sample 4 12 pressure, sample 28 12 pressure]

splitLine :: Stroke
splitLine = Stroke [sample 4 12 0.6, sample 16 12 0.6, sample 28 12 0.6]

peaksAndValleys :: Paper
peaksAndValleys = Paper (PaperSettings 2 1 white 1 42)
  [PaperCell 1 black 0, PaperCell 0 black 0]

render :: OilPastel -> PastelState -> Stroke -> Paper -> IO (Paper, PastelState)
render brush state stroke = either die pure . drawStroke brush state stroke

pigment :: Paper -> Double
pigment = sum . map cellPigmentAmount . paperCells

paintedCount :: Paper -> Int
paintedCount = length . filter ((> 0) . cellPigmentAmount) . paperCells

near :: Double -> Double -> Bool
near left right = abs (left - right) < 1e-9

nearPaper :: Paper -> Paper -> Bool
nearPaper left right = length leftCells == length rightCells && and (zipWith nearCell leftCells rightCells)
  where
    leftCells = paperCells left
    rightCells = paperCells right
    nearCell a b = near (cellPigmentAmount a) (cellPigmentAmount b)
      && and [near (component (cellPigmentColor a)) (component (cellPigmentColor b)) | component <- [red, green, blue]]

validPPM :: Paper -> Bool
validPPM paper = case words (encodePPM paper) of
  "P3" : "32" : "24" : "255" : components ->
    length components == 32 * 24 * 3
      && all (\value -> value >= 0 && value <= 255) (map read components :: [Int])
  _ -> False

inRangeColors :: [RGB]
inRangeColors = colorsFrom [0, 0.25, 0.5, 0.75, 1]

sampleColors :: [RGB]
sampleColors = colorsFrom [-10, -0.25, 0, 0.5, 1, 1.25, 10]

colorsFrom :: [Double] -> [RGB]
colorsFrom values = [RGB r g b | r <- values, g <- values, b <- values]

isInRange :: RGB -> Bool
isInRange (RGB r g b) = all (\component -> component >= 0 && component <= 1) [r, g, b]
