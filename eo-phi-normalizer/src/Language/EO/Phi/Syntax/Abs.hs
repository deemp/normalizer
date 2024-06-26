-- File generated by the BNF Converter (bnfc 2.9.5).

{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- | The abstract syntax of language Syntax.

module Language.EO.Phi.Syntax.Abs where

import Prelude (String)
import qualified Prelude as C (Eq, Ord, Show, Read)
import qualified Data.String

import qualified Data.Data    as C (Data, Typeable)
import qualified GHC.Generics as C (Generic)

data Program = Program [Binding]
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data Object
    = Formation [Binding]
    | Application Object [Binding]
    | ObjectDispatch Object Attribute
    | GlobalObject
    | ThisObject
    | Termination
    | MetaSubstThis Object Object
    | MetaObject MetaId
    | MetaFunction MetaFunctionName Object
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data Binding
    = AlphaBinding Attribute Object
    | EmptyBinding Attribute
    | DeltaBinding Bytes
    | DeltaEmptyBinding
    | LambdaBinding Function
    | MetaBindings MetaId
    | MetaDeltaBinding MetaId
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data Attribute
    = Phi | Rho | Label LabelId | Alpha AlphaIndex | MetaAttr MetaId
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data RuleAttribute = ObjectAttr Attribute | DeltaAttr | LambdaAttr
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data PeeledObject = PeeledObject ObjectHead [ObjectAction]
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data ObjectHead
    = HeadFormation [Binding] | HeadGlobal | HeadThis | HeadTermination
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

data ObjectAction
    = ActionApplication [Binding] | ActionDispatch Attribute
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic)

newtype Bytes = Bytes String
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic, Data.String.IsString)

newtype Function = Function String
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic, Data.String.IsString)

newtype LabelId = LabelId String
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic, Data.String.IsString)

newtype AlphaIndex = AlphaIndex String
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic, Data.String.IsString)

newtype MetaId = MetaId String
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic, Data.String.IsString)

newtype MetaFunctionName = MetaFunctionName String
  deriving (C.Eq, C.Ord, C.Show, C.Read, C.Data, C.Typeable, C.Generic, Data.String.IsString)

