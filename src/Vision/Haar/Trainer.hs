{-# LANGUAGE MultiParamTypeClasses #-}

module Vision.Haar.Trainer (
    -- * Types & constructors
      TrainingImage (..)
    -- * Weak classifier selector
    , selectHaarClassifier
    -- * Impure utilities
    , train
    ) where

import Debug.Trace

import Control.Parallel.Strategies
import Data.Function
import Data.Int
import Data.List
import System.Directory (getDirectoryContents)
import System.FilePath (FilePath, (</>))

import AI.Learning.AdaBoost (
      TrainingTest (..), Classifier (..)
    , Weight, StrongClassifier, adaBoost
    )
import Vision.Haar.Classifier (HaarClassifier (..))
import Vision.Haar.Feature (HaarFeature, features, compute)
import Vision.Haar.Window (Win, win, windowWidth, windowHeight)
import Vision.Image.GreyImage (GreyImage, save, load, resize)
import Vision.Image.IntegralImage (integralImage)
import Vision.Primitive (Size (..), Rect (..))

-- | Contains a training image with its 'IntegralImage'.
data TrainingImage = TrainingImage {
      tiWindow :: !Win
    , tiValid :: !Bool
    }

instance TrainingTest TrainingImage Bool where
    tClass = tiValid

instance Classifier HaarClassifier TrainingImage Bool where
    cClass classifier image = cClass classifier (tiWindow image)

-- | Builds an 'HaarClassifier' which make the best score in classifying the set
-- of tests and weights given.
-- The classifier selection can benefit from parallel computing.
selectHaarClassifier :: [(TrainingImage, Weight)] -> (HaarClassifier, Weight)
selectHaarClassifier tests =
    -- Selects the best classifier over all features.
    minimumBy weight bestClassifiers
  where
    -- Selects the best classifier for each feature, using parallel computing.
    bestClassifiers =
        let parStrategy = evalTuple2 rseq rseq
        in parMap parStrategy bestClassifier features
    
    -- Selects the best classifier configuration for a feature.
    bestClassifier = minimumBy weight . featureClassifiers

    -- Lists all possibles classifier configurations associated with theirs
    -- error for a feature and the set of tests.
    featureClassifiers feature =
        -- The first computed classifier will give "False" for each test, so
        -- its error score is the weight of valid tests.
        fst $ foldl' (\(cs, trueError) (val, w) -> 
            let trueError' = trueError - w
                falseError' = 1.0 - trueError'
                c1 = (HaarClassifier feature val True, trueError')
                c2 = (HaarClassifier feature val False, falseError')
            in (c1 : c2 : cs, trueError')
        ) ([], weightValid) (featureValuesSorted feature tests)

    -- Sums the weight of all valid tests.
    weightValid = sum $ map snd $ filter (tiValid . fst) tests
    
    weight = compare `on` snd

-- | Computes all feature\'s values with a set of tests, sorted.
-- Keeps the test weight. Negative for valid tests, positive for valid tests.
featureValuesSorted :: HaarFeature -> [(TrainingImage, Weight)]
                       -> [(Int64, Weight)]
featureValuesSorted feature =
    sortBy value . map computeValue
  where
    -- Computes the feature value and its weight.
    computeValue (t, w) =
        let w' = if tiValid t
            then w
            else -w
        in (compute feature (tiWindow t), w')
    
    value = compare `on` fst

-- | Trains a strong classifier from directory of tests containing two
-- directories (bad & good).
train :: FilePath -> Int -> FilePath -> IO ()
train directory steps savePath = do
    putStrLn "Loading images ..."
    good <- loadIntegrals True (directory </> "good")
    putStrLn "\tgood/ loaded"
    bad <- loadIntegrals False (directory </> "bad")
    putStrLn "\tbad/ loaded"
    let tests = good ++ bad

    putStrLn "Train classifier ..."
    let classifier = adaBoost steps tests selectHaarClassifier
    print classifier

    putStrLn "Save classifier ..."
    writeFile savePath $ show classifier
  where
    loadIntegrals valid = fmap (trainingImages valid) . loadImages

    loadImages dir = do
        paths <- getDirectoryContents $ dir
        mapM (loadImage . (dir </>)) (excludeHidden paths)

    loadImage path = do
        img <- load path
        return $ resize img $ Size windowWidth windowHeight

    excludeHidden = filter $ ((/=) '.') . head

-- | Accepts a list of images with a boolean indicating if the image is valid.
-- Compute the 'IntegralImage' and initialises a full image 'Win' for each
-- image.
trainingImages :: Bool -> [GreyImage] -> [TrainingImage]
trainingImages valid = map trainingImage
  where
    rect = Rect 0 0 windowWidth windowHeight
    trainingImage image =
        let ii = integralImage image id
            squaredIi = integralImage image (^2)
            window = win rect ii squaredIi
        in TrainingImage window valid