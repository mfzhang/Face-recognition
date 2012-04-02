{-# LANGUAGE BangPatterns #-}

module Vision.Haar.Window (
    -- * Types & constructors
      Win (..), win
    -- * Constants
    , windowWidth, windowHeight
    -- * Functions
    , getValue, normalizeSum, featuresPos, windows
    ) where

import Debug.Trace
    
import Data.Array.Unboxed (UArray, listArray, (!))
import Data.Int
import Data.Word

import qualified Vision.Image as I
import qualified Vision.Image.IntegralImage as II
import Vision.Primitive (Point (..), Size (..), Rect (..))

-- | Used as a structure to iterate an image.
data Win = Win {
      wRect :: !Rect
    , wIntegral :: !II.IntegralImage
    -- | Values ([0;255]) of the commulative normal distribution for each 
    -- pixels values ([0; 255]) based on the average and the standard derivation
    -- of the 'Win' pixels values.
    -- 
    -- Used to equalize the values inside 'Win' histogram. This will return the
    -- value of the pixel of value @x@ in the equalized distribution:
    -- 
    -- > wDistibution win ! x
    , wDistibution :: !(UArray Int Double)
    }

-- Default window\'s size.
windowWidth, windowHeight :: Int
windowWidth = 24
windowHeight = 24

windowPixels :: Int64
windowPixels = int64 $ windowWidth * windowWidth

-- | Constructs a new 'Win' object, computing the commulative normal
-- distribution using the standard derivation and the average of pixels values.
win :: Rect -> II.IntegralImage -> II.IntegralImage -> Win
win rect@(Rect x y w h) integral squaredIntegral =
    Win rect integral distribution
    --deriv (round avg)
  where
    avg = valuesSum / n
    sig = max 1 $ sqrt $ (squaresSum / n) - avg^2
    n = double $ w * h
    valuesSum = double $ II.sumRectangle integral rect
    squaresSum = double $ II.sumRectangle squaredIntegral rect
    -- The normal distribution function
    normal x = (1 / (sig * sqrt (2 * pi))) * exp (-(x - avg)^2 / (2 * sig^2))
    distribution =
        listArray (0, 255) $ tail $ scanl (\acc x -> acc + normal x) 0 [0..255]

-- | Gets the value of a point (as in the default window) inside the window,
-- takes care of the window\'s size ratio, so two points in two windows of
-- different sizes can be compared.
getValue :: Win -> Point -> Int64
Win (Rect winX winY w h) integral _ `getValue` Point x y =
    ratio $ integral `I.getPixel` Point destX destY
  where
    -- New coordinates with the window's ratio
    destX = winX + (x * w `quot` windowWidth)
    destY = winY + (y * h `quot` windowHeight)
    n = int64 $ w * h
    -- Sum with the window\'s size ratio
    ratio v = v * windowPixels `quot` n
{-# INLINE getValue #-}
    
-- | Sums 's' over 'n' pixels normalized by the window\'s standard derivation.
-- This way, two sums inside two windows of different size/standard derivation
-- can be compared.
normalizeSum :: Win -> Int -> Int64 -> Int64
normalizeSum (Win _ _ distribution) n s =
    round $ double n * (normalize $ s `quot` int64 n) * 255
  where
    normalize p = distribution ! int p
    -- Pixel\'s value normalized with the double of the standard derivation
    -- (95% of pixels values, following a normal distribution), averaged
    -- around 127.
--     normalize p = (p - (avg - 2*deriv)) * 255 `quot` (4*deriv)
{-# INLINE normalizeSum #-}

-- | Lists all features positions and sizes inside the default window.
featuresPos :: Int -> Int -> [Rect]
featuresPos minWidth minHeight =
    rectangles minWidth minHeight windowWidth windowHeight

-- | Lists all windows for any positions and sizes inside an image.
windows :: II.IntegralImage -> II.IntegralImage -> [Win]
windows integral squaredIntegral =
    let Size w h = I.getSize integral
    in [ win rect integral squaredIntegral |
            rect <- rectangles windowWidth windowHeight w h
       ]

-- | Lists all rectangle positions and sizes inside a rectangle of
-- width * height.
rectangles minWidth minHeight width height =
    [ Rect x y w h |
          x <- [0,incrX..width-minWidth]
        , y <- [0,incrY..height-minHeight]
        , w <- [minWidth,minWidth+incrWidth..width-x]
        , h <- [minHeight,minHeight+incrHeight..height-y]
    ]
  where
    incrMult = 5
    incrX = 1 * incrMult
    incrY = 1 * incrMult
    incrWidth = minWidth * incrMult
    incrHeight = minHeight * incrMult

double :: Integral a => a -> Double
double = fromIntegral
int :: Integral a => a -> Int
int = fromIntegral
int64 :: Integral a => a -> Int64
int64 = fromIntegral
word16 :: Integral a => a -> Word16
word16 = fromIntegral