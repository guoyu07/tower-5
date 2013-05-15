{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE QuasiQuotes #-}

module Ivory.Tower.Test.FooBarTower where

import Ivory.Language

import Ivory.Tower

[ivory|
struct foo_state
  { foo_member :: Stored Uint8
  }
|]

[ivory|
struct bar_state
  { bar_member :: Stored Uint8
  }
|]

[ivory|
struct some_other_type
  { some_other_member :: Stored Uint8
  }
|]

fooBarTypes :: Module
fooBarTypes = package "fooBarTypes" $ do
  defStruct (Proxy :: Proxy "foo_state")
  defStruct (Proxy :: Proxy "bar_state")

someOtherModule :: Module
someOtherModule= package "someOtherModule" $ do
  defStruct (Proxy :: Proxy "some_other_type")


fooSourceTask :: DataSource (Struct "foo_state") -> TaskConstructor
fooSourceTask fooSource = withContext $ do
    fooWriter <- withDataWriter fooSource "fooSource"
    p <- withPeriod 250
    taskModuleDef $ depend fooBarTypes
    taskBody $ do
      state <- local (istruct [])
      handlers $ onTimer p $ \_now -> do
        v <- deref (state ~> foo_member)
        store (state ~> foo_member) (v + 1)
        writeData fooWriter (constRef state)

barSourceTask :: ChannelSource (Struct "bar_state") -> TaskConstructor
barSourceTask barSource = withContext $ do
    barEmitter <- withChannelEmitter barSource "barSource"
    p <- withPeriod 125
    taskModuleDef $ depend fooBarTypes
    taskBody $ do
      state <- local (istruct [])
      handlers $ onTimer p $ \_now -> do
        v <- deref (state ~> bar_member)
        store (state ~> bar_member) (v + 1)
        emit barEmitter (constRef state)

fooBarSinkTask :: DataSink (Struct "foo_state")
               -> ChannelSink (Struct "bar_state")
               -> TaskConstructor
fooBarSinkTask fooSink barSink = do
  barReceiver <- withChannelReceiver barSink "barSink"
  withContext $ do
    fooReader   <- withDataReader    fooSink "fooSink"
    taskModuleDef $ depend fooBarTypes
    taskBody $ do
      latestFoo <- local (istruct [])
      latestSum <- local (ival 0)
      handlers $ onChannel barReceiver $ \latestBar -> do
        readData fooReader latestFoo
        bmember <- deref (latestBar ~> bar_member)
        fmember <- deref (latestFoo ~> foo_member)
        store latestSum (bmember + fmember)

fooBarTower :: Tower ()
fooBarTower = do
  (source_f, sink_f) <- dataport
  (source_b, sink_b) <- channel

  task "fooSourceTask"  $ fooSourceTask source_f
  task "barSourceTask"  $ barSourceTask source_b
  task "fooBarSinkTask" $ fooBarSinkTask sink_f sink_b

  addModule fooBarTypes
  addModule someOtherModule
