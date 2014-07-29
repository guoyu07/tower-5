{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE StandaloneDeriving #-}

module Ivory.Tower.AST.Handler
  ( Handler(..)
  ) where

import Ivory.Tower.AST.Event
import Ivory.Tower.Types.Unique

data Handler =
  Handler
    { handler_name       :: Unique
    , handler_annotation :: String
    , handler_evt        :: Event -- XXX change to Trigger or something along those lines
    } deriving (Eq, Show)

