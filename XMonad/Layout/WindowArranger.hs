{-# OPTIONS_GHC -fglasgow-exts #-} -- for deriving Typeable
{-# LANGUAGE PatternGuards, FlexibleInstances, MultiParamTypeClasses, TypeSynonymInstances #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  XMonad.Layout.WindowArranger
-- Copyright   :  (c) Andrea Rossato 2007
-- License     :  BSD-style (see xmonad/LICENSE)
--
-- Maintainer  :  andrea.rossato@unibz.it
-- Stability   :  unstable
-- Portability :  unportable
--
-- This is a pure layout modifier that will let you move and resize
-- windows with the keyboard in any layout.
-----------------------------------------------------------------------------

module XMonad.Layout.WindowArranger
    ( -- * Usage
      -- $usage
      windowArranger
    , WindowArrangerMsg (..)
    , memberFromList
    , listFromList
    , diff
    ) where

import XMonad
import qualified XMonad.StackSet as S
import XMonad.Layout.LayoutModifier
import XMonad.Util.XUtils (fi)

import Control.Arrow
import Data.List
import Data.Maybe

-- $usage
-- You can use this module with the following in your
-- @~\/.xmonad\/xmonad.hs@:
--
-- > import XMonad.Layout.WindowArranger
-- > myLayout = layoutHook defaultConfig
-- > main = xmonad defaultConfig { layoutHook = windowArranger myLayout }
--
-- For more detailed instructions on editing the layoutHook see:
--
-- "XMonad.Doc.Extending#Editing_the_layout_hook"
--
-- You may also want to define some key binding to move or resize
-- windows. These are good defaults:
--
-- >        , ((modMask x .|. controlMask              , xK_s    ), sendMessage  Arrange         )
-- >        , ((modMask x .|. controlMask .|. shiftMask, xK_s    ), sendMessage  DeArrange       )
-- >        , ((modMask x .|. controlMask              , xK_Left ), sendMessage (MoveLeft      1))
-- >        , ((modMask x .|. controlMask              , xK_Right), sendMessage (MoveRight     1))
-- >        , ((modMask x .|. controlMask              , xK_Down ), sendMessage (MoveDown      1))
-- >        , ((modMask x .|. controlMask              , xK_Up   ), sendMessage (MoveUp        1))
-- >        , ((modMask x                 .|. shiftMask, xK_Left ), sendMessage (IncreaseLeft  1))
-- >        , ((modMask x                 .|. shiftMask, xK_Right), sendMessage (IncreaseRight 1))
-- >        , ((modMask x                 .|. shiftMask, xK_Down ), sendMessage (IncreaseDown  1))
-- >        , ((modMask x                 .|. shiftMask, xK_Up   ), sendMessage (IncreaseUp    1))
-- >        , ((modMask x .|. controlMask .|. shiftMask, xK_Left ), sendMessage (DecreaseLeft  1))
-- >        , ((modMask x .|. controlMask .|. shiftMask, xK_Right), sendMessage (DecreaseRight 1))
-- >        , ((modMask x .|. controlMask .|. shiftMask, xK_Down ), sendMessage (DecreaseDown  1))
-- >        , ((modMask x .|. controlMask .|. shiftMask, xK_Up   ), sendMessage (DecreaseUp    1))
--
-- For detailed instructions on editing your key bindings, see
-- "XMonad.Doc.Extending#Editing_key_bindings".

-- | A layout modifier to float the windows in a workspace
windowArranger :: l a -> ModifiedLayout WindowArranger l a
windowArranger = ModifiedLayout (WA True [])

data WindowArrangerMsg = DeArrange
                       | Arrange
                       | IncreaseLeft  Int
                       | IncreaseRight Int
                       | IncreaseUp    Int
                       | IncreaseDown  Int
                       | DecreaseLeft  Int
                       | DecreaseRight Int
                       | DecreaseUp    Int
                       | DecreaseDown  Int
                       | MoveLeft      Int
                       | MoveRight     Int
                       | MoveUp        Int
                       | MoveDown      Int
                         deriving ( Typeable )
instance Message WindowArrangerMsg

data ArrangedWindow a = WR   (a, Rectangle)
                      | AWR  (a, Rectangle)
                        deriving (Read, Show)

data WindowArranger a = WA Bool [ArrangedWindow a] deriving (Read, Show)

instance (Show a, Read a, Eq a) => LayoutModifier WindowArranger a where
    pureModifier (WA True []  ) _  _              wrs = arrangeWindows wrs

    pureModifier (WA True awrs) _ (S.Stack w _ _) wrs = curry process  wrs awrs
        where
          wins         = map fst     *** map awrWin
          update (a,r) = mkNewAWRs a *** removeAWRs r >>> uncurry (++)
          process      = wins &&&  id  >>> first diff >>> uncurry update >>>
                         replaceWR wrs >>> putOnTop w >>> map fromAWR &&& Just . WA True

    pureModifier _ _ _ wrs = (wrs, Nothing)

    pureMess (WA True (wr:wrs)) m
        -- increase the window's size
        | Just (IncreaseRight i) <- fm, (win, Rectangle x y w h) <- fa = res win  x         y        (w + fi i) h
        | Just (IncreaseLeft  i) <- fm, (win, Rectangle x y w h) <- fa = res win (x - fi i) y        (w + fi i) h
        | Just (IncreaseUp    i) <- fm, (win, Rectangle x y w h) <- fa = res win  x        (y - fi i) w        (h + fi i)
        | Just (IncreaseDown  i) <- fm, (win, Rectangle x y w h) <- fa = res win  x         y         w        (h + fi i)
        -- decrease the window's size
        | Just (DecreaseRight i) <- fm, (win, Rectangle x y w h) <- fa = res win (x + fi i) y        (chk  w i) h
        | Just (DecreaseLeft  i) <- fm, (win, Rectangle x y w h) <- fa = res win  x         y        (chk  w i) h
        | Just (DecreaseUp    i) <- fm, (win, Rectangle x y w h) <- fa = res win  x         y         w        (chk h i)
        | Just (DecreaseDown  i) <- fm, (win, Rectangle x y w h) <- fa = res win  x        (y + fi i) w        (chk h i)
        --move the window around
        | Just (MoveRight     i) <- fm, (win, Rectangle x y w h) <- fa = res win (x + fi i) y         w         h
        | Just (MoveLeft      i) <- fm, (win, Rectangle x y w h) <- fa = res win (x - fi i) y         w         h
        | Just (MoveUp        i) <- fm, (win, Rectangle x y w h) <- fa = res win  x        (y - fi i) w         h
        | Just (MoveDown      i) <- fm, (win, Rectangle x y w h) <- fa = res win  x        (y + fi i) w         h

        where res wi x y w h = Just . WA True $ AWR (wi,Rectangle x y w h):wrs
              fm             = fromMessage m
              fa             = fromAWR     wr
              chk        x y = fi $ max 1 (fi x - y)

    pureMess (WA _ l) m
        | Just DeArrange <- fromMessage m = Just $ WA False l
        | Just Arrange   <- fromMessage m = Just $ WA True  l
        | otherwise                       = Nothing

arrangeWindows :: [(a,Rectangle)] -> ([(a, Rectangle)], Maybe (WindowArranger a))
arrangeWindows wrs = (wrs, Just $ WA True (map WR wrs))

fromAWR :: ArrangedWindow a -> (a, Rectangle)
fromAWR (WR   x) = x
fromAWR (AWR  x) = x

awrWin :: ArrangedWindow a -> a
awrWin = fst . fromAWR

getAWR :: Eq a => a -> [ArrangedWindow a] -> [ArrangedWindow a]
getAWR = memberFromList awrWin (==)

getWR ::  Eq a => a -> [(a,Rectangle)] -> [(a,Rectangle)]
getWR = memberFromList fst (==)

mkNewAWRs :: Eq a => [a] -> [(a,Rectangle)] -> [ArrangedWindow a]
mkNewAWRs w wrs = map WR . concatMap (flip getWR wrs) $ w

removeAWRs :: Eq a => [a] -> [ArrangedWindow a] -> [ArrangedWindow a]
removeAWRs = listFromList awrWin notElem

putOnTop :: Eq a => a -> [ArrangedWindow a] -> [ArrangedWindow a]
putOnTop w awrs = awr ++ nawrs
    where awr   = getAWR w awrs
          nawrs = filter ((/=w) . awrWin) awrs

replaceWR :: Eq a => [(a, Rectangle)] -> [ArrangedWindow a] -> [ArrangedWindow a]
replaceWR wrs = foldr r []
    where r x xs
              | WR wr <- x = case fst wr `elemIndex` map fst wrs of
                               Just i  -> (WR $ wrs !! i):xs
                               Nothing -> x:xs
              | otherwise  = x:xs

-- | Given a function to be applied to each member of a list, and a
-- function to check a condition by processing this transformed member
-- with the members of a list, you get the list of members that
-- satisfy the condition.
listFromList :: (b -> c) -> (c -> [a] -> Bool) -> [a] -> [b] -> [b]
listFromList f g l = foldr (h l) []
    where h x y ys = if g (f y) x then y:ys else ys

-- | Given a function to be applied to each member of ta list, and a
-- function to check a condition by processing this transformed member
-- with something, you get the first member that satisfy the condition,
-- or an empty list.
memberFromList :: (b -> c) -> (c -> a -> Bool) -> a -> [b] -> [b]
memberFromList f g l = foldr (h l) []
    where h x y ys = if g (f y) x then [y] else ys

-- | Get the list of elements to be deleted and the list ef elements to
-- be added to the first list in order to get the second list.
diff :: Eq a => ([a],[a]) -> ([a],[a])
diff (x,y) = (x \\ y, y \\ x)