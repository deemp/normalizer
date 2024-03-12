{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Language.EO.Phi.Dataize (dataizeStep, dataizeRecursively) where

import Data.List (find)
import Data.String.Interpolate (i)
import Language.EO.Phi (printTree)
import Language.EO.Phi.Rules.Common (Context, applyRules, bytesToInt, extendContextWith, intToBytes)
import Language.EO.Phi.Syntax.Abs (
  AlphaIndex (AlphaIndex),
  Attribute (Alpha, Phi, Rho),
  Binding (AlphaBinding, DeltaBinding, LambdaBinding),
  Bytes (Bytes),
  Function (Function),
  Object (Application, Formation, ObjectDispatch, Termination),
 )

-- | Perform one step of dataization to the object (if possible).
dataizeStep :: Context -> Object -> Either Object Bytes
dataizeStep ctx obj@(Formation bs)
  | Just (DeltaBinding bytes) <- find isDelta bs = Right bytes
  | Just (LambdaBinding (Function funcName)) <- find isLambda bs = Left (fst $ evaluateBuiltinFun ctx funcName obj ())
  | Just (AlphaBinding Phi decoratee) <- find isPhi bs = dataizeStep (extendContextWith obj ctx) decoratee
  | otherwise = Left obj -- TODO: Need to differentiate between `Left` due to no matches and a "partial Right"
 where
  isDelta (DeltaBinding _) = True
  isDelta _ = False
  isLambda (LambdaBinding _) = True
  isLambda _ = False
  isPhi (AlphaBinding Phi _) = True
  isPhi _ = False
dataizeStep ctx (Application obj bindings) = case dataizeStep ctx obj of
  Left dataized -> Left $ Application dataized bindings
  Right _ -> error ("Application on bytes upon dataizing:\n  " <> printTree obj)
dataizeStep ctx (ObjectDispatch obj attr) = case dataizeStep ctx obj of
  Left dataized -> Left $ ObjectDispatch dataized attr
  Right _ -> error ("Dispatch on bytes upon dataizing:\n  " <> printTree obj)
dataizeStep _ obj = Left obj

-- | State of evaluation is not needed yet, but it might be in the future
type EvaluationState = ()

-- | Recursively perform normalization and dataization until we get bytes in the end.
dataizeRecursively :: Context -> Object -> Either Object Bytes
dataizeRecursively ctx obj = case applyRules ctx obj of
  [normObj] -> case dataizeStep ctx normObj of
    Left stillObj
      | stillObj == normObj -> Left stillObj -- dataization changed nothing
      | otherwise -> dataizeRecursively ctx stillObj -- partially dataized
    Right bytes -> Right bytes
  objs -> error errMsg -- Left Termination
   where
    errMsg =
      "Expected 1 result from normalization but got "
        <> show (length objs)
        <> ":\n"
        <> unlines (map (("  - " ++) . printTree) objs)
        <> "\nFor the input:\n  "
        <> printTree obj

-- | Given normalization context, a function on data (bytes interpreted as integers), an object,
-- and the current state of evaluation, returns the new object and a possibly modified state.
evaluateDataizationFun :: Context -> (Int -> Int -> Int) -> Object -> EvaluationState -> (Object, EvaluationState)
evaluateDataizationFun ctx func obj _state = (result, ())
 where
  lhs = dataizeRecursively ctx (ObjectDispatch obj Rho)
  rhs = dataizeRecursively ctx (ObjectDispatch obj (Alpha (AlphaIndex "α0")))
  result = case (lhs, rhs) of
    (Right l, Right r) -> let (Bytes bytes) = intToBytes (bytesToInt r `func` bytesToInt l) in [i|Φ.org.eolang.float(Δ ⤍ #{bytes})|]
    _ -> Termination

-- | Like `evaluateDataizationFun` but specifically for the built-in functions.
-- This function is not safe. It returns undefined for unknown functions
evaluateBuiltinFun :: Context -> String -> Object -> EvaluationState -> (Object, EvaluationState)
evaluateBuiltinFun ctx "Plus" = evaluateDataizationFun ctx (+)
evaluateBuiltinFun ctx "Times" = evaluateDataizationFun ctx (*)
evaluateBuiltinFun _ _ = const $ const (undefined, ())
