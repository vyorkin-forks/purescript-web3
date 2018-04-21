module Network.Ethereum.Web3.Types.Types
       ( BlockNumber(..)
       , ChainCursor(..)
       , Block(..)
       , Transaction(..)
       , TransactionReceipt(..)
       , TransactionOptions(..)
       , defaultTransactionOptions
       , _from
       , _to
       , _data
       , _value
       , _gas
       , _gasPrice
       , ETH
       , _nonce
       , forkWeb3
       , forkWeb3'
       , runWeb3
       , Web3(..)
       , Web3Par
       , throwWeb3
       , Filter
       , defaultFilter
       , _address
       , _topics
       , _fromBlock
       , _toBlock
       , FilterId
       , EventAction(..)
       , Change(..)
       , FalseOrObject(..)
       , unFalseOrObject
       , SyncStatus(..)
       , MethodName
       , RPCMessage
       , mkRPCMessage
       , Response(..)
       , Web3Error(..)
       , RpcError(..)
       , CallError(..)
       ) where

import Prelude

import Control.Alt (class Alt)
import Control.Alternative (class Alternative, class Plus, (<|>))
import Control.Monad.Aff (Aff, Fiber, ParAff, forkAff, liftEff', throwError)
import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Monad.Eff (kind Effect)
import Control.Monad.Eff.Class (class MonadEff)
import Control.Monad.Eff.Exception (Error, throwException)
import Control.Monad.Error.Class (class MonadThrow, catchError)
import Control.Monad.Except (ExceptT, except, runExceptT)
import Control.Monad.Reader (class MonadAsk, class MonadReader, ReaderT, ask, runReaderT)
import Control.Monad.Rec.Class (class MonadRec)
import Control.Parallel.Class (class Parallel, parallel, sequential)
import Data.Either (Either(..))
import Data.Foreign (F, Foreign, ForeignError(..), fail, isNull, readBoolean, readString)
import Data.Foreign.Class (class Decode, class Encode, decode, encode)
import Data.Foreign.Generic (defaultOptions, genericDecode, genericEncode)
import Data.Foreign.Index (readProp)
import Data.Foreign.NullOrUndefined (NullOrUndefined(..), unNullOrUndefined)
import Data.Functor.Compose (Compose)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Eq (genericEq)
import Data.Generic.Rep.Show (genericShow)
import Data.Lens.Lens (Lens', Lens, lens)
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, unwrap)
import Data.Ordering (invert)
import Data.Record as Record
import Data.Symbol (SProxy(..))
import Network.Ethereum.Types (Address, BigNumber, HexString)
import Network.Ethereum.Web3.Types.EtherUnit (class EtherUnit, NoPay, Value, Wei, convert)
import Network.Ethereum.Web3.Types.Provider (Provider)
import Simple.JSON (read)

--------------------------------------------------------------------------------
-- * Block
--------------------------------------------------------------------------------

newtype BlockNumber = BlockNumber BigNumber

derive newtype instance showBlockNumber :: Show BlockNumber
derive newtype instance eqBlockNumber :: Eq BlockNumber
derive newtype instance ordBlockNumber :: Ord BlockNumber
derive newtype instance decodeBlockNumber :: Decode BlockNumber
derive newtype instance encodeBlockNumber :: Encode BlockNumber
derive instance newtypeBlockNumber :: Newtype BlockNumber _

-- | Refers to a particular block time, used when making calls, transactions, or watching for events.
data ChainCursor =
    Latest
  | Pending
  | Earliest
  | BN BlockNumber

derive instance genericChainCursor :: Generic ChainCursor _

instance eqChainCursor :: Eq ChainCursor where
  eq = genericEq

instance showChainCursor :: Show ChainCursor where
  show = genericShow

instance ordChainCursor :: Ord ChainCursor where
  compare Pending Pending = EQ
  compare Latest Latest = EQ
  compare Earliest Earliest = EQ
  compare (BN a) (BN b) = compare a b
  compare _ Pending = LT
  compare Pending Latest = GT
  compare _ Latest = LT
  compare Earliest _ = LT
  compare a b = invert $ compare b a

instance encodeChainCursor :: Encode ChainCursor where
  encode cm = case cm of
    Latest -> encode "latest"
    Pending -> encode "pending"
    Earliest -> encode "earliest"
    BN n -> encode n

newtype Block
  = Block { difficulty :: BigNumber
          , extraData :: HexString
          , gasLimit :: BigNumber
          , gasUsed :: BigNumber
          , hash :: HexString
          , logsBloom :: HexString
          , miner :: HexString
          , nonce :: HexString
          , number :: BigNumber
          , parentHash :: HexString
          , receiptsRoot :: HexString
          , sha3Uncles :: HexString
          , size :: BigNumber
          , stateRoot :: HexString
          , timestamp :: BigNumber
          , totalDifficulty :: BigNumber
          , transactions :: Array HexString
          , transactionsRoot :: HexString
          , uncles :: Array HexString
          }

derive instance genericBlock :: Generic Block _
derive instance newtypeBlock :: Newtype Block _
derive instance eqBlock :: Eq Block

instance showBlock :: Show Block where
  show = genericShow

instance decodeBlock :: Decode Block where
  decode x = catchError (genericDecode decodeOpts x)
                -- if this attempt fails for any reason pass back the original error
                \origError -> catchError tryKovanAuthorHack (\_ -> throwError origError)
    where
      decodeOpts = defaultOptions { unwrapSingleConstructors = true }
      tryKovanAuthorHack = do
        rec <- except $ read x
        let blockRec = Record.delete (SProxy :: SProxy "author") rec
                     # Record.insert (SProxy :: SProxy "nonce") rec.author
        pure $ Block blockRec



--------------------------------------------------------------------------------
-- * Transaction
--------------------------------------------------------------------------------

newtype Transaction =
  Transaction { hash :: HexString
              , nonce :: BigNumber
              , blockHash :: HexString
              , blockNumber :: BlockNumber
              , transactionIndex :: BigNumber
              , from :: Address
              , to :: NullOrUndefined Address
              , value :: Value Wei
              , gas :: BigNumber
              , gasPrice :: BigNumber
              , input :: HexString
              }

derive instance genericTransaction :: Generic Transaction _
derive instance newtypeTransaction :: Newtype Transaction _
derive instance eqTransaction :: Eq Transaction

instance showTransaction :: Show Transaction where
  show = genericShow

instance decodeTransaction :: Decode Transaction where
  decode x = genericDecode (defaultOptions { unwrapSingleConstructors = true }) x

--------------------------------------------------------------------------------
-- * TransactionReceipt
--------------------------------------------------------------------------------

newtype TransactionReceipt =
  TransactionReceipt { transactionHash :: HexString
                     , transactionIndex :: BigNumber
                     , blockHash :: HexString
                     , blockNumber :: BlockNumber
                     , cumulativeGasUsed :: BigNumber
                     , gasUsed :: BigNumber
                     , contractAddress :: NullOrUndefined Address
                     , logs :: Array Change
                     , status :: String -- 0x0 for fail, 0x1 for success
                     }

derive instance genericTxReceipt :: Generic TransactionReceipt _
derive instance newtypeTxReceipt :: Newtype TransactionReceipt _
derive instance eqTxReceipt :: Eq TransactionReceipt

instance showTxReceipt :: Show TransactionReceipt where
  show = genericShow

instance decodeTxReceipt :: Decode TransactionReceipt where
  decode = genericDecode (defaultOptions { unwrapSingleConstructors = true })

--------------------------------------------------------------------------------
-- * TransactionOptions
--------------------------------------------------------------------------------

newtype TransactionOptions u =
  TransactionOptions { from :: NullOrUndefined Address
                     , to :: NullOrUndefined Address
                     , value :: NullOrUndefined (Value u)
                     , gas :: NullOrUndefined BigNumber
                     , gasPrice :: NullOrUndefined BigNumber
                     , data :: NullOrUndefined HexString
                     , nonce :: NullOrUndefined BigNumber
                     }

derive instance genericTransactionOptions :: Generic (TransactionOptions u) _
derive instance newtypeTransactionOptions :: Newtype (TransactionOptions u) _
derive instance eqTransactionOptions :: Eq (TransactionOptions u)

instance showTransactionOptions :: Show (TransactionOptions u) where
  show = genericShow

instance encodeTransactionOptions :: Encode (TransactionOptions u) where
  encode = genericEncode (defaultOptions { unwrapSingleConstructors = true })

defaultTransactionOptions :: TransactionOptions NoPay
defaultTransactionOptions =
  TransactionOptions { from : NullOrUndefined Nothing
                     , to : NullOrUndefined Nothing
                     , value : NullOrUndefined Nothing
                     , gas : NullOrUndefined Nothing
                     , gasPrice : NullOrUndefined Nothing
                     , data : NullOrUndefined Nothing
                     , nonce : NullOrUndefined Nothing
                     }
-- * Lens Boilerplate
_from :: forall u. Lens' (TransactionOptions u) (Maybe Address)
_from = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.from)
          (\(TransactionOptions txOpts) addr -> TransactionOptions $ txOpts {from = NullOrUndefined addr})

_to :: forall u. Lens' (TransactionOptions u) (Maybe Address)
_to = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.to)
           (\(TransactionOptions txOpts) addr -> TransactionOptions $ txOpts {to = NullOrUndefined addr})

_data :: forall u. Lens' (TransactionOptions u) (Maybe HexString)
_data = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.data)
           (\(TransactionOptions txOpts) dat -> TransactionOptions $ txOpts {data = NullOrUndefined dat})

_value :: forall u. EtherUnit (Value u) => Lens (TransactionOptions u) (TransactionOptions Wei) (Maybe (Value u)) (Maybe (Value Wei))
_value = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.value)
           (\(TransactionOptions txOpts) val -> TransactionOptions $ txOpts {value = NullOrUndefined $ map convert val})

_gas :: forall u. Lens' (TransactionOptions u) (Maybe BigNumber)
_gas = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.gas)
           (\(TransactionOptions txOpts) g -> TransactionOptions $ txOpts {gas = NullOrUndefined g})

_gasPrice :: forall u. Lens' (TransactionOptions u) (Maybe BigNumber)
_gasPrice = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.gasPrice)
              (\(TransactionOptions txOpts) gp -> TransactionOptions $ txOpts {gasPrice = NullOrUndefined gp})

_nonce :: forall u. Lens' (TransactionOptions u) (Maybe BigNumber)
_nonce = lens (\(TransactionOptions txOpt) -> unNullOrUndefined $ txOpt.nonce)
           (\(TransactionOptions txOpts) n -> TransactionOptions $ txOpts {nonce = NullOrUndefined n})

--------------------------------------------------------------------------------
-- * Node Synchronisation
--------------------------------------------------------------------------------

newtype SyncStatus = SyncStatus
    { startingBlock :: BigNumber
    , currentBlock :: BigNumber
    , highestBlock :: BigNumber
    }

derive instance genericSyncStatus :: Generic SyncStatus _
derive instance newtypeSyncStatus :: Newtype SyncStatus _
derive instance eqSyncStatus :: Eq SyncStatus

instance decodeSyncStatus :: Decode SyncStatus where
    decode = genericDecode (defaultOptions { unwrapSingleConstructors = true })

instance showSyncStatus :: Show SyncStatus where
    show = genericShow

--------------------------------------------------------------------------------
-- * Web3
--------------------------------------------------------------------------------

foreign import data ETH :: Effect

-- | A monad for asynchronous Web3 actions

newtype Web3 e a = Web3 (ReaderT Provider (ExceptT Web3Error (Aff (eth :: ETH | e))) a)

derive newtype instance functorWeb3 :: Functor (Web3 e)

derive newtype instance applyWeb3 :: Apply (Web3 e)

derive newtype instance applicativeWeb3 :: Applicative (Web3 e)

derive newtype instance bindWeb3 :: Bind (Web3 e)

derive newtype instance monadWeb3 :: Monad (Web3 e)

derive newtype instance monadEffWeb3 :: MonadEff (eth :: ETH | e) (Web3 e)

derive newtype instance monadAffWeb3 ∷ MonadAff (eth :: ETH | e) (Web3 e)

derive newtype instance monadThrowWeb3 :: MonadThrow Web3Error (Web3 e)

derive newtype instance monadAskWeb3 :: MonadAsk Provider (Web3 e)

derive newtype instance monadReaderWeb3 :: MonadReader Provider (Web3 e)

derive newtype instance monadRecWeb3 :: MonadRec (Web3 e)

newtype Web3Par e a = Web3Par (ReaderT Provider (Compose (ParAff (eth :: ETH | e)) (Either Web3Error)) a)

derive newtype instance functorWeb3Par :: Functor (Web3Par e)

derive newtype instance applyWeb3Par :: Apply (Web3Par e)

derive newtype instance applicativeWeb3Par :: Applicative (Web3Par e)

instance monadParWeb3 :: Parallel (Web3Par e) (Web3 e) where
  parallel (Web3 m) = Web3Par (parallel m)
  sequential (Web3Par m) = Web3 (sequential m)

derive newtype instance altParWeb3 :: Alt (Web3Par e)

derive newtype instance plusParWeb3 :: Plus (Web3Par e)

derive newtype instance alternativeParWeb3 :: Alternative (Web3Par e)

throwWeb3 :: forall e a. Error -> Web3 e a
throwWeb3 = liftAff <<< liftEff' <<< throwException

-- | Run an asynchronous `ETH` action
runWeb3 :: forall e a . Provider -> Web3 e a -> Aff (eth :: ETH | e) (Either Web3Error a)
runWeb3 p (Web3 action) = runExceptT (runReaderT action p)

-- | Fork an asynchronous `ETH` action
forkWeb3 :: forall e a .
            Provider
         -> Web3 e a
         -> Aff (eth :: ETH | e) (Fiber (eth :: ETH | e) (Either Web3Error a))
forkWeb3 p = forkAff <<< runWeb3 p

-- | Fork an asynchronous `ETH` action inside Web3 monad
forkWeb3' :: forall e a. Web3 e a -> Web3 e (Fiber (eth :: ETH | e) (Either Web3Error a))
forkWeb3' web3Action = do
  p <- ask
  liftAff $ forkWeb3 p web3Action

--------------------------------------------------------------------------------
-- * Filters
--------------------------------------------------------------------------------

-- | Low-level event filter data structure
newtype Filter = Filter
  { address   :: NullOrUndefined Address
  , topics    :: NullOrUndefined (Array (NullOrUndefined HexString))
  , fromBlock :: ChainCursor
  , toBlock   :: ChainCursor
  }

derive instance genericFilter :: Generic Filter _
derive instance newtypeFilter :: Newtype Filter _

instance showFilter :: Show Filter where
  show = genericShow

instance eqFilter :: Eq Filter where
  eq = genericEq

instance encodeFilter :: Encode Filter where
  encode x = genericEncode (defaultOptions { unwrapSingleConstructors = true }) x

defaultFilter :: Filter
defaultFilter = Filter { address: NullOrUndefined Nothing
                       , topics: NullOrUndefined Nothing
                       , fromBlock: Latest
                       , toBlock: Latest
                       }

_address :: Lens' Filter (Maybe Address)
_address = lens (\(Filter f) -> unNullOrUndefined f.address)
          (\(Filter f) addr -> Filter $ f {address = NullOrUndefined addr})

_topics :: Lens' Filter (Maybe (Array (Maybe HexString)))
_topics = lens (\(Filter f) -> map unNullOrUndefined <$> unNullOrUndefined f.topics)
          (\(Filter f) ts -> Filter $ f {topics = NullOrUndefined (map NullOrUndefined <$> ts)})

_fromBlock :: Lens' Filter ChainCursor
_fromBlock = lens (\(Filter f) -> f.fromBlock)
          (\(Filter f) b -> Filter $ f {fromBlock = b})

_toBlock :: Lens' Filter ChainCursor
_toBlock = lens (\(Filter f) -> f.toBlock)
          (\(Filter f) b -> Filter $ f {toBlock = b})

-- | Used by the ethereum client to identify the filter you are querying
newtype FilterId = FilterId HexString

derive instance genericFilterId :: Generic FilterId _

instance showFilterId :: Show FilterId where
  show = genericShow

instance eqFilterId :: Eq FilterId where
  eq = genericEq

instance encodeFilterId :: Encode FilterId where
  encode x = genericEncode (defaultOptions { unwrapSingleConstructors = true }) x

instance decodeFilterId :: Decode FilterId where
  decode x = genericDecode (defaultOptions { unwrapSingleConstructors = true }) x


--------------------------------------------------------------------------------
-- | EventAction
--------------------------------------------------------------------------------

-- | Represents a flag to continue or discontinue listening to the filter
data EventAction = ContinueEvent
                 -- ^ Continue to listen events
                 | TerminateEvent
                 -- ^ Terminate event listener

derive instance genericEventAction :: Generic EventAction _

instance showEventAction :: Show EventAction where
  show = genericShow

instance eqEventAction :: Eq EventAction where
  eq = genericEq


--------------------------------------------------------------------------------
-- * Raw Event Log Changes
--------------------------------------------------------------------------------

-- | Changes pulled by low-level call 'eth_getFilterChanges', 'eth_getLogs',
-- | and 'eth_getFilterLogs'
newtype Change = Change
  { logIndex         :: HexString
  , transactionIndex :: HexString
  , transactionHash  :: HexString
  , blockHash        :: HexString
  , blockNumber      :: BlockNumber
  , address          :: Address
  , data             :: HexString
  , topics           :: Array HexString
  }

derive instance genericChange :: Generic Change _
derive instance newtypeChange :: Newtype Change _

instance showChange :: Show Change where
  show = genericShow

instance eqChange :: Eq Change where
  eq = genericEq

instance decodeChange :: Decode Change where
  decode x = genericDecode (defaultOptions { unwrapSingleConstructors = true }) x


--------------------------------------------------------------------------------
-- * Json Decode Types
--------------------------------------------------------------------------------

-- | Newtype wrapper around `Maybe` to handle cases where Web3 passes back
-- | either `false` or some data type
newtype FalseOrObject a = FalseOrObject (Maybe a)

derive instance newtypeFalseOrObj :: Newtype (FalseOrObject a) _
derive instance eqFalseOrObj :: Eq a => Eq (FalseOrObject a)
derive instance ordFalseOrObj :: Ord a => Ord (FalseOrObject a)
derive instance genericFalseOrObj :: Generic (FalseOrObject a) _

instance showFalseOrObj :: Show a => Show (FalseOrObject a) where
    show x = "(FalseOrObject " <> show (unwrap x) <> ")"

unFalseOrObject :: forall a. FalseOrObject a -> Maybe a
unFalseOrObject (FalseOrObject a) = a

readFalseOrObject :: forall a. (Foreign -> F a) -> Foreign -> F (FalseOrObject a)
readFalseOrObject f value = do
    isBool <- catchError ((\_ -> true) <$> readBoolean value) (\_ -> pure false)
    if isBool then
        pure $ FalseOrObject Nothing
      else
        FalseOrObject <<< Just <$> f value

instance decodeFalseOrObj :: Decode a => Decode (FalseOrObject a) where
    decode x = readFalseOrObject decode x

--------------------------------------------------------------------------------
-- * Web3 RPC
--------------------------------------------------------------------------------

type MethodName = String

newtype RPCMessage a =
  RPCMessage { jsonrpc :: String
             , id :: Int
             , method :: MethodName
             , params :: a
             }

derive instance genericRPCMessage :: Generic (RPCMessage a) _

instance encodeRPCMessage :: Encode a => Encode (RPCMessage a) where
  encode x = genericEncode (defaultOptions { unwrapSingleConstructors = true }) x

instance decodeRPCMessage :: Decode a => Decode (RPCMessage a) where
  decode x = genericDecode (defaultOptions { unwrapSingleConstructors = true }) x

mkRPCMessage :: MethodName -> Int -> Array Foreign -> RPCMessage (Array Foreign)
mkRPCMessage name reqId ps =
  RPCMessage { jsonrpc : "2.0"
             , id : reqId
             , method : name
             , params : ps
             }

newtype Response a = Response (Either Web3Error a)

instance decodeResponse' :: Decode a => Decode (Response a) where
  decode a = Response <$> ((Left <$> decode a) <|> (Right <$> (readProp "result" a >>= decode)))

--------------------------------------------------------------------------------
-- * Subscriptions
--------------------------------------------------------------------------------

newtype SubscriptionId = SubscriptionId HexString

derive instance genericSubscriptionId :: Generic SubscriptionId _

derive newtype instance showSubscriptionId :: Show SubscriptionId
derive newtype instance eqSubscriptionId :: Eq SubscriptionId
derive newtype instance decodeSubscriptionId :: Decode SubscriptionId

newtype Subscription a =
  Subscription { subscription :: SubscriptionId
               , result :: a
               }

derive instance genericSubscription :: Generic (Subscription a) _

derive instance functorSubscription :: Functor Subscription

instance showSubscription :: Show a => Show (Subscription a) where
  show = genericShow

instance eqSubscription :: Eq a => Eq (Subscription a) where
  eq = genericEq

instance decodeSubscription :: Decode a => Decode (Subscription a) where
  decode x = genericDecode (defaultOptions { unwrapSingleConstructors = true }) x

--------------------------------------------------------------------------------
-- * Errors
--------------------------------------------------------------------------------

data CallError =
  NullStorageError { signature :: String
                   , _data :: HexString
                   }

derive instance genericCallError :: Generic CallError _

instance showCallError :: Show CallError where
  show = genericShow

instance eqCallError :: Eq CallError where
  eq = genericEq

newtype RpcError =
  RpcError { code     :: Int
           , message  :: String
           }

derive instance newtypeRPCError :: Newtype RpcError _

derive instance genericRpcError :: Generic RpcError _

instance showRpcError :: Show RpcError where
  show = genericShow

instance eqRpcError :: Eq RpcError where
  eq = genericEq

instance decodeRpcError :: Decode RpcError where
  decode x = genericDecode (defaultOptions { unwrapSingleConstructors = true }) x

data Web3Error =
    Rpc RpcError
  | RemoteError String
  | ParserError String
  | NullError

derive instance genericWeb3Error :: Generic Web3Error _

instance showWeb3Error :: Show Web3Error where
  show = genericShow

instance eqWeb3Error :: Eq Web3Error where
  eq = genericEq

instance decodeWeb3Error :: Decode Web3Error where
  decode x = (map Rpc $ readProp "error" x >>= decode) <|> nullParser
    where
      nullParser = do
        res <- readProp "result" x
        if isNull res
          then pure NullError
          else readString res >>= \r -> fail (TypeMismatch "NullError" r)
