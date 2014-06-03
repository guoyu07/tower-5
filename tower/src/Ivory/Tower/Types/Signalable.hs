{-# LANGUAGE TypeFamilies #-}

module Ivory.Tower.Types.Signalable
  ( Signalable(..)
  , NoSignals(..)
  ) where

class Signalable p where
  data SignalType p
  signalName :: SignalType p -> String

-- Utility class
data NoSignals = NoSignals
instance Signalable NoSignals where
  data SignalType NoSignals = NoSignal deriving (Show)
  signalName = show

