{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}

module Ivory.Tower.Task where

import Text.Printf

import Ivory.Language
import Ivory.Stdlib (when)

import Ivory.Tower.Types
import Ivory.Tower.Monad
import Ivory.Tower.Node

-- Public Task Definitions -----------------------------------------------------
instance Channelable TaskSt where
  nodeChannelEmitter  = taskChannelEmitter
  nodeChannelReceiver = taskChannelReceiver

taskChannelEmitter :: forall n area p . (SingI n, IvoryArea area)
        => ChannelSource n area -> Node TaskSt p (ChannelEmitter n area, String)
taskChannelEmitter chsrc = do
  nodename <- getNodeName
  unique   <- freshname -- May not be needed.
  let chid    = unChannelSource chsrc
      emitName = printf "emitFromTask_%s_chan%d%s" nodename (chan_id chid) unique
      externEmit :: Def ('[ConstRef s area] :-> IBool)
      externEmit = externProc emitName
      procEmit :: TaskSchedule -> Def ('[ConstRef s area] :-> IBool)
      procEmit schedule = proc emitName $ \ref -> body $ do
        r <- tsch_mkEmitter schedule emitter ref
        ret r
      emitter  = ChannelEmitter
        { ce_chid         = chid
        , ce_extern_emit  = call  externEmit
        , ce_extern_emit_ = call_ externEmit
        }
  taskStAddModuleDef $ \sch -> do
    incl (procEmit sch)
  return (emitter, emitName)

taskChannelReceiver :: forall n area p
                     . (SingI n, IvoryArea area, IvoryZero area)
                    => ChannelSink n area
                    -> Node TaskSt p (ChannelReceiver n area, String)
taskChannelReceiver chsnk = do
  nodename <- getNodeName
  unique   <- freshname -- May not be needed.
  let chid = unChannelSink chsnk
      rxName = printf "receiveFromTask_%s_chan%d%s" nodename (chan_id chid) unique
      externRx :: Def ('[Ref s area] :-> IBool)
      externRx = externProc rxName
      procRx :: TaskSchedule -> Def ('[Ref s area] :-> IBool)
      procRx schedule = proc rxName $ \ref -> body $ do
        r <- tsch_mkReceiver schedule rxer ref
        ret r
      rxer = ChannelReceiver
        { cr_chid      = chid
        , cr_extern_rx = call externRx
        }
  taskStAddModuleDef $ \sch -> do
    incl (procRx sch)
  return (rxer, rxName)

------

instance DataPortable TaskSt where
  nodeDataReader = taskDataReader
  nodeDataWriter = taskDataWriter

taskDataReader :: forall area p . (IvoryArea area)
               => DataSink area -> Node TaskSt p (DataReader area, String)
taskDataReader dsnk = do
  nodename <- getNodeName
  unique   <- freshname -- May not be needed.
  let dpid = unDataSink dsnk
      readerName = printf "read_%s_dataport%d%s" nodename (dp_id dpid) unique
      externReader :: Def ('[Ref s area] :-> ())
      externReader = externProc readerName
      procReader :: TaskSchedule -> Def ('[Ref s area] :-> ())
      procReader schedule = proc readerName $ \ref -> body $
        tsch_mkDataReader schedule dsnk ref
      reader = DataReader
        { dr_dpid   = dpid
        , dr_extern = call_ externReader
        }
  taskStAddModuleDef $ \sch -> do
    incl (procReader sch)
  return (reader, readerName)

taskDataWriter :: forall area p . (IvoryArea area)
               => DataSource area -> Node TaskSt p (DataWriter area, String)
taskDataWriter dsrc = do
  nodename <- getNodeName
  unique   <- freshname -- May not be needed.
  let dpid = unDataSource dsrc
      writerName = printf "write_%s_dataport%d%s" nodename (dp_id dpid) unique
      externWriter :: Def ('[ConstRef s area] :-> ())
      externWriter = externProc writerName
      procWriter :: TaskSchedule -> Def ('[ConstRef s area] :-> ())
      procWriter schedule = proc writerName $ \ref -> body $
        tsch_mkDataWriter schedule dsrc ref
      writer = DataWriter
        { dw_dpid   = dpid
        , dw_extern = call_ externWriter
        }
  taskStAddModuleDef $ \sch -> do
    incl (procWriter sch)
  return (writer, writerName)

--------------------------------------------------------------------------------

-- | Track Ivory dependencies used by the 'Ivory.Tower.Tower.taskBody' created
--   in the 'Ivory.Tower.Types.Task' context.
taskModuleDef :: ModuleDef -> Task p ()
taskModuleDef = taskStAddModuleDefUser

taskDependency :: Task p ModuleDef
taskDependency = do
  n <- getNode
  let fakepkg = package (taskst_pkgname_user n) (return ())
  return (depend fakepkg)

-- | Specify the stack size, in bytes, of the 'Ivory.Tower.Tower.taskBody'
--   created in the 'Ivory.Tower.Types.Task' context.
withStackSize :: Integer -> Task p ()
withStackSize stacksize = do
  s <- getTaskSt
  case taskst_stacksize s of
    Nothing -> setTaskSt $ s { taskst_stacksize = Just stacksize }
    Just _  -> getNodeName >>= \name ->
               fail ("Cannot use withStackSize more than once in task named "
                  ++  name)

-- | Specify an OS priority level of the 'Ivory.Tower.Tower.taskBody' created in
--   the 'Ivory.Tower.Types.Task' context. Implementation at the backend
--   defined by the 'Ivory.Tower.Types.OS' implementation.
withPriority :: Integer -> Task p ()
withPriority p = do
  s <- getTaskSt
  case taskst_priority s of
    Nothing -> setTaskSt $ s { taskst_priority = Just p }
    Just _  -> getNodeName >>= \name ->
               fail ("Cannot use withPriority more than once in task named "
                     ++ name)

-- | Add an Ivory Module to the result of this Tower compilation, from the
--   Task context.
withModule :: Module -> Task p ()
withModule m = do
  s <- getTaskSt
  setTaskSt $ s { taskst_extern_mods = m:(taskst_extern_mods s)}


-- | Create an 'Ivory.Tower.Types.OSGetTimeMillis' in the context of a 'Task'.
withGetTimeMillis :: Task p OSGetTimeMillis
withGetTimeMillis = do
  os <- getOS
  return $ OSGetTimeMillis (os_getTimeMillis os)

-- | Create a global (e.g. not stack) variable which is private to the task
--   code.
taskLocal :: (IvoryArea area) => Name -> Task p (Ref Global area)
taskLocal n = tlocalAux n Nothing

-- | like 'TaskLocal' but you can provide an 'Init' initialization value.
taskLocalInit :: (IvoryArea area) => Name -> Init area -> Task p (Ref Global area)
taskLocalInit n i = tlocalAux n (Just i)

-- | Private helper implements 'taskLocal' and 'taskLocalInit'
tlocalAux :: (IvoryArea area) => Name -> Maybe (Init area) -> Task p (Ref Global area)
tlocalAux n i = do
  f <- freshname
  let m = area (n ++ f) i
  -- Task Locals should only ever be used privately in user code.
  taskStAddModuleDefUser $ private $ defMemArea m
  return (addrOf m)

-- | Task Initialization handler. Called once when the Tower system initializes.
taskInit :: ( forall s . Ivory (ProcEffects s ()) () ) -> Task p ()
taskInit i = do
  s <- getTaskSt
  n <- getNodeName
  case taskst_taskinit s of
    Nothing -> setTaskSt $ s { taskst_taskinit = Just (initproc n) }
    Just _ -> (err n)
  where
  err nodename = error ("multiple taskInit definitions in task named "
                          ++ nodename)
  initproc nodename = proc ("taskInit_" ++ nodename) $ body i

-- | Channel event handler. Called once per received event. Gives event by
--   reference.
onChannel :: forall n area p
           . (IvoryArea area, IvoryZero area)
          => ChannelReceiver n area
          -> (forall s s' . ConstRef s area -> Ivory (ProcEffects s' ()) ())
          -> Task p ()
onChannel chrxer k = mkOnChannel chrxer $ \name ->
  proc name $ \ref -> body $ k ref

-- | Channel event handler. Like 'onChannel', but for 'Stored' type events,
--   which can be given by value.
onChannelV :: forall n t p
           . (IvoryVar t, IvoryArea (Stored t), IvoryZero (Stored t))
          => ChannelReceiver n (Stored t)
          -> (forall s . t -> Ivory (ProcEffects s ()) ())
          -> Task p ()
onChannelV chrxer k = mkOnChannel chrxer $ \name ->
  proc name $ \ref -> body $ deref ref >>= k

-- | Private helper function used to implement 'onChannel' and 'onChannelV'
mkOnChannel :: forall n area p
             . (IvoryArea area, IvoryZero area)
            => ChannelReceiver n area
            -> (forall s . Name -> Def ('[ConstRef s area] :-> ()))
            -> Task p ()
mkOnChannel chrxer mkproc = do
  n <- getNodeName
  f <- freshname
  let name = printf "channelhandler_%s_chan%d%s" n (chan_id (cr_chid chrxer)) f
      callback :: Def ('[ConstRef s area] :-> ())
      callback = mkproc name
  taskStAddTaskHandler $ TaskHandler
    { th_scheduler = do
        ref <- local izero
        success <- cr_extern_rx chrxer ref
        when success $ call_ callback (constRef ref)
    , th_moddef = incl callback
    }

-- | Timer period handler. Calls the event handler at a fixed period, giving the
--   current time as the event handler argument. All times in ms.
onPeriod :: Integer -> (forall s  . Uint32 -> Ivory (ProcEffects s ()) ()) -> Task p ()
onPeriod interval k = do
  per <- mkPeriod interval
  n <- getNodeName
  f <- freshname
  let name = printf "periodhandler_%s_interval%d%s" n (per_interval per) f
      callback :: Def ('[Uint32]:->())
      callback = proc name $ \time -> body $ k time
  taskStAddTaskHandler $ TaskHandler
    { th_scheduler = do
        success <- per_tick per
        when success $ do
          now <- per_tnow per
          call_ callback now
    , th_moddef = incl callback
    }

-- | Private: interal, makes a Period from an integer, stores
--   generated code
mkPeriod :: Integer -> Task p Period
mkPeriod per = do
  st <- getTaskSt
  setTaskSt $ st { taskst_periods = per : (taskst_periods st)}
  os <- getOS
  n <- freshname
  let (p, initdef, mdef) = os_mkPeriodic os per n
  nodeStAddCodegen initdef mdef
  return p

