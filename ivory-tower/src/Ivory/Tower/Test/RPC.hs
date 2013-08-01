{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE QuasiQuotes #-}

module Ivory.Tower.Test.RPC where

import Ivory.Language
import Ivory.Stdlib
import Ivory.Tower
import Ivory.Tower.RPC

[ivory|
struct foo
  { foo_member :: Stored Uint8
  }
|]

[ivory|
struct bar
  { bar_member :: Stored Uint8
  }
|]

fooBarTypes :: Module
fooBarTypes = package "fooBarTypes" $ do
  defStruct (Proxy :: Proxy "foo")
  defStruct (Proxy :: Proxy "bar")

client :: (SingI n, SingI m)
       => ChannelSource n (Struct "foo")
       -> ChannelSink   m (Struct "bar")
       -> Task ()
client t f = do
  send1 <- taskLocal "send1"
  send2 <- taskLocal "send2"
  gotSum <- taskLocal "gotSum"
  runner <- rpc t f "sampleClient" $ do
    rpcStart [ send (constRef send1) ]
    rx1 <- rpcLocal "rx1"
    rpcBlock rx1
      [ send (constRef send2) ]
    rx2 <- rpcLocal "rx2"
    rpcBlock rx2 [
      liftIvory $ do
        r1 <- deref (rx1 ~> bar_member)
        r2 <- deref (rx2 ~> bar_member)
        store gotSum (r1 + r2)
      ]

  onPeriod 100 $ \_time -> do
    a <- rpcActive runner
    unless a $ do
      store (send1 ~> foo_member) 10
      store (send2 ~> foo_member) 33
      rpcBegin runner

-- Server adds one to a number, but only returns the result at
-- a fixed 250ms period boundary.
server :: (SingI n, SingI m)
       => ChannelSink   n (Struct "foo")
       -> ChannelSource m (Struct "bar")
       -> Task ()
server inCh outCh = do
  ostream  <- withChannelEmitter  outCh "ostream"
  istream  <- withChannelReceiver inCh  "istream"
  tosend   <- taskLocalInit "tosend" (ival false)
  lastrxed <- taskLocal "lastrxed"
  err      <- taskLocalInit "error" (ival 0)
  onPeriod 250 $ \_time -> do
    p <- deref tosend
    when p $ do
      got <- deref (lastrxed ~> foo_member)
      out <- local (istruct [ bar_member .= ival (got + 1) ])
      emit_ ostream (constRef out)
      store tosend false
  onChannel istream $ \v -> do
    full <- deref tosend
    unless full $ do
      refCopy lastrxed v
      store tosend true
    -- Otherwise, drop messages and log an error.
    when full $ do
      (e :: Uint32) <- deref err
      store err (e + 1)

rpcTower :: Tower ()
rpcTower = do
  callCh <- channel
  respCh <- channel
  task "client" $ client (src callCh) (snk respCh)
  task "server" $ server (snk callCh) (src respCh)

  addDepends fooBarTypes
  addModule fooBarTypes
