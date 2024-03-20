{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE QuasiQuotes #-}

module Language.EO.Phi.Metrics where

import Control.Lens ((+=))
import Control.Monad (forM_)
import Control.Monad.State (State, execState, runState)
import Data.Aeson (KeyValue ((.=)), ToJSON (..), Value, withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (FromJSON (..), Parser)
import Data.Generics.Labels ()
import Data.List (groupBy, intercalate)
import Data.Traversable (forM)
import GHC.Generics (Generic)
import Language.EO.Phi.Rules.Common ()
import Language.EO.Phi.Syntax.Abs
import Language.EO.Phi.TH
import Data.String.Interpolate

data Metrics a = Metrics
  { formations :: a
  , dataless :: a
  , applications :: a
  , dispatches :: a
  }
  deriving stock (Show, Generic, Eq)

$(deriveJSON ''Metrics)

makeBinaryOperation :: (a -> b -> c) -> Metrics a -> Metrics b -> Metrics c
makeBinaryOperation op x y =
  Metrics
    { formations = x.formations `op` y.formations
    , dataless = x.dataless `op` y.dataless
    , applications = x.applications `op` y.applications
    , dispatches = x.dispatches `op` y.dispatches
    }

makeUnaryOperation :: (a -> b) -> Metrics a -> Metrics b
makeUnaryOperation op Metrics{..} =
  Metrics
    { formations = op formations
    , dataless = op dataless
    , applications = op applications
    , dispatches = op dispatches
    }

instance (Num a) => Num (Metrics a) where
  (+) :: Metrics a -> Metrics a -> Metrics a
  (+) = makeBinaryOperation (+)
  (-) :: Metrics a -> Metrics a -> Metrics a
  (-) = makeBinaryOperation (-)
  (*) :: Metrics a -> Metrics a -> Metrics a
  (*) = makeBinaryOperation (*)
  negate :: Metrics a -> Metrics a
  negate = makeUnaryOperation negate
  abs :: Metrics a -> Metrics a
  abs = makeUnaryOperation abs
  signum :: Metrics a -> Metrics a
  signum = makeUnaryOperation signum
  fromInteger :: Integer -> Metrics a
  fromInteger x = error [i|Cannot construct metrics from an integer #{x}|]

-- | Used in cases when a change in metrics requires division by zero.
nan :: (Fractional a) => a
nan = -1e9

calculateChange :: (Fractional a, Eq a) => a -> a -> a
calculateChange x y
  | x == 0 || x == nan || y == nan = nan
  | otherwise = x / y

instance (Fractional a, Eq a) => Fractional (Metrics a) where
  fromRational :: Rational -> Metrics a
  fromRational _ = 0
  (/) :: Metrics a -> Metrics a -> Metrics a
  (/) = makeBinaryOperation calculateChange

instance (Num a) => Semigroup (Metrics a) where
  (<>) :: Metrics a -> Metrics a -> Metrics a
  (<>) = (+)

instance (Num a) => Monoid (Metrics a) where
  mempty :: Metrics a
  mempty = 0

type MetricsCount = Metrics Int

data BindingMetrics = BindingMetrics
  { name :: String
  , metrics :: MetricsCount
  }
  deriving (Show, Generic, Eq)

$(deriveJSON ''BindingMetrics)

count :: (a -> Bool) -> [a] -> Int
count x = length . filter x

getHeight :: [Binding] -> [Int] -> Int
getHeight bindings heights
  | hasDeltaBinding = 1
  | otherwise = heightAttributes
 where
  heightAttributes =
    case heights of
      [] -> 0
      _ -> minimum heights + 1
  hasDeltaBinding = not $ null [undefined | DeltaBinding _ <- bindings]

countDataless :: Int -> Int
countDataless x
  | x == 0 || x > 2 = 1
  | otherwise = 0

class Inspectable a where
  inspect :: a -> State MetricsCount Int

instance Inspectable Binding where
  inspect :: Binding -> State MetricsCount Int
  inspect = \case
    AlphaBinding _ obj -> do
      inspect obj
    _ -> pure 0

instance Inspectable Object where
  inspect :: Object -> State MetricsCount Int
  inspect = \case
    Formation bindings -> do
      #formations += 1
      heights <- forM bindings inspect
      let height = getHeight bindings heights
      #dataless += countDataless height
      pure height
    Application obj bindings -> do
      #applications += 1
      _ <- inspect obj
      forM_ bindings inspect
      pure 0
    ObjectDispatch obj _ -> do
      #dispatches += 1
      _ <- inspect obj
      pure 0
    _ -> pure 0

type Path = [String]

-- >>> splitStringOn '.' "abra.cada.bra"
-- ["abra","cada","bra"]
--
-- >>> splitStringOn '.' ""
-- []
splitStringOn :: Char -> String -> Path
splitStringOn sep = filter (/= [sep]) . groupBy (\a b -> a /= sep && b /= sep)

splitPath :: String -> Path
splitPath = splitStringOn '.'

data BindingsByPathMetrics = BindingsByPathMetrics
  { path :: Path
  , bindingsMetrics :: [BindingMetrics]
  }
  deriving (Show, Generic, Eq)

instance FromJSON BindingsByPathMetrics where
  parseJSON :: Value -> Parser BindingsByPathMetrics
  parseJSON = withObject "BindingsByPathMetrics" $ \obj -> do
    path <- splitPath <$> (obj .: "path")
    bindingsMetrics <- obj .: "bindings-metrics"
    pure BindingsByPathMetrics{..}

instance ToJSON BindingsByPathMetrics where
  toJSON :: BindingsByPathMetrics -> Value
  toJSON BindingsByPathMetrics{..} =
    Aeson.object
      [ "path" .= intercalate "." path
      , "bindings-metrics" .= bindingsMetrics
      ]

data ObjectMetrics = ObjectMetrics
  { bindingsByPathMetrics :: Maybe BindingsByPathMetrics
  , thisObjectMetrics :: MetricsCount
  }
  deriving (Show, Generic, Eq)

$(deriveJSON ''ObjectMetrics)

-- | Get metrics for an object
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ξ, α0 ↦ Φ.org.eolang.bytes( Δ ⤍ 00- ) ⟧"
-- Metrics {dataless = 0, applications = 1, formations = 1, dispatches = 3}
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ξ, Δ ⤍ 00- ⟧"
-- Metrics {dataless = 0, applications = 0, formations = 1, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ξ, α1 ↦ ⟦ Δ ⤍ 00- ⟧ ⟧"
-- Metrics {dataless = 0, applications = 0, formations = 2, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ξ, α1 ↦ ⟦ α2 ↦ ⟦ Δ ⤍ 00- ⟧ ⟧ ⟧"
-- Metrics {dataless = 0, applications = 0, formations = 3, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ Δ ⤍ 00- ⟧"
-- Metrics {dataless = 0, applications = 0, formations = 1, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ⟦ α0 ↦ ∅ ⟧ ⟧"
-- Metrics {dataless = 0, applications = 0, formations = 2, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ⟦ α0 ↦ ⟦ α0 ↦ ∅ ⟧ ⟧ ⟧"
-- Metrics {dataless = 1, applications = 0, formations = 3, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ α0 ↦ ⟦ α0 ↦ ⟦ α0 ↦ ⟦ α0 ↦ ∅ ⟧ ⟧ ⟧ ⟧"
-- Metrics {dataless = 2, applications = 0, formations = 4, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ org ↦ ⟦ ⟧ ⟧"
-- Metrics {dataless = 1, applications = 0, formations = 2, dispatches = 0}
--
-- >>> getThisObjectMetrics "⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧.e ⟧"
-- Metrics {dataless = 1, applications = 1, formations = 5, dispatches = 5}
getThisObjectMetrics :: Object -> MetricsCount
getThisObjectMetrics obj = execState (inspect obj) mempty

-- | Get an object by a path within a given object.
--
-- If no object is accessible by the path, return a prefix of the path that led to a non-formation when the remaining path wasn't empty.
-- >>> flip getObjectByPath ["org", "eolang"] "⟦ org ↦ ⟦ eolang ↦ ⟦ x ↦ ⟦ φ ↦ Φ.org.eolang.bool ( α0 ↦ Φ.org.eolang.bytes (Δ ⤍ 01-) ) ⟧, z ↦ ⟦ y ↦ ⟦ x ↦ ∅, φ ↦ ξ.x ⟧, φ ↦ Φ.org.eolang.bool ( α0 ↦ Φ.org.eolang.bytes (Δ ⤍ 01-) ) ⟧, λ ⤍ Package ⟧, λ ⤍ Package ⟧⟧"
-- Right (Formation [AlphaBinding (Label (LabelId "x")) (Formation [AlphaBinding Phi (Application (ObjectDispatch (ObjectDispatch (ObjectDispatch GlobalObject (Label (LabelId "org"))) (Label (LabelId "eolang"))) (Label (LabelId "bool"))) [AlphaBinding (Alpha (AlphaIndex "\945\&0")) (Application (ObjectDispatch (ObjectDispatch (ObjectDispatch GlobalObject (Label (LabelId "org"))) (Label (LabelId "eolang"))) (Label (LabelId "bytes"))) [DeltaBinding (Bytes "01-")])])]),AlphaBinding (Label (LabelId "z")) (Formation [AlphaBinding (Label (LabelId "y")) (Formation [EmptyBinding (Label (LabelId "x")),AlphaBinding Phi (ObjectDispatch ThisObject (Label (LabelId "x")))]),AlphaBinding Phi (Application (ObjectDispatch (ObjectDispatch (ObjectDispatch GlobalObject (Label (LabelId "org"))) (Label (LabelId "eolang"))) (Label (LabelId "bool"))) [AlphaBinding (Alpha (AlphaIndex "\945\&0")) (Application (ObjectDispatch (ObjectDispatch (ObjectDispatch GlobalObject (Label (LabelId "org"))) (Label (LabelId "eolang"))) (Label (LabelId "bytes"))) [DeltaBinding (Bytes "01-")])])]),LambdaBinding (Function "Package")])
--
-- >>> flip getObjectByPath ["a"] "⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧.e ⟧"
-- Right (ObjectDispatch (Formation [AlphaBinding (Label (LabelId "b")) (Formation [EmptyBinding (Label (LabelId "c")),AlphaBinding (Label (LabelId "d")) (Formation [AlphaBinding Phi (ObjectDispatch (ObjectDispatch ThisObject Rho) (Label (LabelId "c")))])]),AlphaBinding (Label (LabelId "e")) (ObjectDispatch (Application (ObjectDispatch ThisObject (Label (LabelId "b"))) [AlphaBinding (Label (LabelId "c")) (Formation [])]) (Label (LabelId "d")))]) (Label (LabelId "e")))
getObjectByPath :: Object -> Path -> Either Path Object
getObjectByPath object path =
  case path of
    [] -> Right object
    (p : ps) ->
      case object of
        Formation bindings ->
          case objectByPath' of
            [] -> Left path
            (x : _) -> Right x
         where
          objectByPath' =
            do
              x <- bindings
              Right obj <-
                case x of
                  AlphaBinding (Alpha (AlphaIndex name)) obj | name == p -> [getObjectByPath obj ps]
                  AlphaBinding (Label (LabelId name)) obj | name == p -> [getObjectByPath obj ps]
                  _ -> [Left path]
              pure obj
        _ -> Left path

-- | Get metrics for bindings of a formation that is accessible by a path within a given object.
--
-- If no formation is accessible by the path, return a prefix of the path that led to a non-formation when the remaining path wasn't empty.
-- >>> flip getBindingsByPathMetrics ["a"] "⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧.e ⟧"
-- Left ["a"]
--
-- >>> flip getBindingsByPathMetrics ["a"] "⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧ ⟧"
-- Right (BindingsByPathMetrics {path = ["a"], bindingsMetrics = [BindingMetrics {name = "b", metrics = Metrics {dataless = 0, applications = 0, formations = 2, dispatches = 2}},BindingMetrics {name = "e", metrics = Metrics {dataless = 1, applications = 1, formations = 1, dispatches = 2}}]})
getBindingsByPathMetrics :: Object -> Path -> Either Path BindingsByPathMetrics
getBindingsByPathMetrics object path =
  case getObjectByPath object path of
    Right (Formation bindings) ->
      let attributes' = flip runState mempty . inspect <$> bindings
          (_, objectMetrics) = unzip attributes'
          bindingsMetrics = do
            x <- zip bindings objectMetrics
            case x of
              (AlphaBinding (Alpha (AlphaIndex name)) _, metrics) -> [BindingMetrics{..}]
              (AlphaBinding (Label (LabelId name)) _, metrics) -> [BindingMetrics{..}]
              _ -> []
       in Right $ BindingsByPathMetrics{..}
    Right _ -> Left path
    Left path' -> Left path'

-- | Get metrics for an object and for bindings of a formation accessible by a given path.
--
-- Combine metrics produced by 'getThisObjectMetrics' and 'getBindingsByPathMetrics'.
--
-- If no formation is accessible by the path, return a prefix of the path that led to a non-formation when the remaining path wasn't empty.
-- >>> flip getObjectMetrics (Just ["a"]) "⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧.e ⟧"
-- Left ["a"]
--
-- >>> flip getObjectMetrics (Just ["a"]) "⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧ ⟧"
-- Right (ObjectMetrics {bindingsByPathMetrics = Just (BindingsByPathMetrics {path = ["a"], bindingsMetrics = [BindingMetrics {name = "b", metrics = Metrics {dataless = 0, applications = 0, formations = 2, dispatches = 2}},BindingMetrics {name = "e", metrics = Metrics {dataless = 1, applications = 1, formations = 1, dispatches = 2}}]}), thisObjectMetrics = Metrics {dataless = 1, applications = 1, formations = 5, dispatches = 4}})
getObjectMetrics :: Object -> Maybe Path -> Either Path ObjectMetrics
getObjectMetrics object path = do
  let thisObjectMetrics = getThisObjectMetrics object
  bindingsByPathMetrics <- forM path $ \path' -> getBindingsByPathMetrics object path'
  pure ObjectMetrics{..}

data ProgramMetrics = ProgramMetrics
  { bindingsByPathMetrics :: Maybe BindingsByPathMetrics
  , programMetrics :: MetricsCount
  }
  deriving (Show, Generic, Eq)

$(deriveJSON ''ProgramMetrics)

-- | Get metrics for a program and for bindings of a formation accessible by a given path.
--
-- Combine metrics produced by 'getThisObjectMetrics' and 'getBindingsByPathMetrics'.
--
-- If no formation is accessible by the path, return a prefix of the path that led to a non-formation when the remaining path wasn't empty.
-- >>> flip getProgramMetrics (Just ["org", "eolang"]) "{⟦ org ↦ ⟦ eolang ↦ ⟦ x ↦ ⟦ φ ↦ Φ.org.eolang.bool ( α0 ↦ Φ.org.eolang.bytes (Δ ⤍ 01-) ) ⟧, z ↦ ⟦ y ↦ ⟦ x ↦ ∅, φ ↦ ξ.x ⟧, φ ↦ Φ.org.eolang.bool ( α0 ↦ Φ.org.eolang.bytes (Δ ⤍ 01-) ) ⟧, λ ⤍ Package ⟧, λ ⤍ Package ⟧⟧ }"
-- Right (ProgramMetrics {bindingsByPathMetrics = Just (BindingsByPathMetrics {path = ["org","eolang"], bindingsMetrics = [BindingMetrics {name = "x", metrics = Metrics {dataless = 0, applications = 2, formations = 1, dispatches = 6}},BindingMetrics {name = "z", metrics = Metrics {dataless = 0, applications = 2, formations = 2, dispatches = 7}}]}), programMetrics = Metrics {dataless = 0, applications = 4, formations = 6, dispatches = 13}})
--
-- >>> flip getProgramMetrics (Just ["a"]) "{⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧.e ⟧}"
-- Left ["a"]
--
-- >>> flip getProgramMetrics (Just ["a"]) "{⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧ ⟧}"
-- Right (ProgramMetrics {bindingsByPathMetrics = Just (BindingsByPathMetrics {path = ["a"], bindingsMetrics = [BindingMetrics {name = "b", metrics = Metrics {dataless = 0, applications = 0, formations = 2, dispatches = 2}},BindingMetrics {name = "e", metrics = Metrics {dataless = 1, applications = 1, formations = 1, dispatches = 2}}]}), programMetrics = Metrics {dataless = 1, applications = 1, formations = 5, dispatches = 4}})
getProgramMetrics :: Program -> Maybe Path -> Either Path ProgramMetrics
getProgramMetrics (Program bindings) path = do
  ObjectMetrics{..} <- getObjectMetrics (Formation bindings) path
  pure ProgramMetrics{programMetrics = thisObjectMetrics, ..}
