{- FOURMOLU_DISABLE -}
-- Copyright EO/Polystat Development Team (c) 2023

-- All rights reserved.

-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:

--     * Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.

--     * Redistributions in binary form must reproduce the above
--       copyright notice, this list of conditions and the following
--       disclaimer in the documentation and/or other materials provided
--       with the distribution.

--     * Neither the name of EO/Polystat Development Team nor the names of other
--       contributors may be used to endorse or promote products derived
--       from this software without specific prior written permission.

-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
-- LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
-- A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
-- OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
-- LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
-- DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
-- THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
-- OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
{- FOURMOLU_ENABLE -}
-- File generated by the BNF Converter (bnfc 2.9.5).

{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
#if __GLASGOW_HASKELL__ <= 708
{-# LANGUAGE OverlappingInstances #-}
#endif

-- | Pretty-printer for Language.

module Language.EO.Phi.Syntax.Print where

import Prelude
  ( ($), (.)
  , Bool(..), (==), (<)
  , Int, Integer, Double, (+), (-), (*)
  , String, (++)
  , ShowS, showChar, showString
  , all, elem, foldr, id, map, null, replicate, shows, span
  )
import Data.Char ( Char, isSpace )
import qualified Language.EO.Phi.Syntax.Abs

-- | The top-level printing method.

printTree :: Print a => a -> String
printTree = render . prt 0

type Doc = [ShowS] -> [ShowS]

doc :: ShowS -> Doc
doc = (:)

render :: Doc -> String
render d = rend 0 False (map ($ "") $ d []) ""
  where
  rend
    :: Int        -- ^ Indentation level.
    -> Bool       -- ^ Pending indentation to be output before next character?
    -> [String]
    -> ShowS
  rend i p = \case
      "["      :ts -> char '[' . rend i False ts
      "("      :ts -> char '(' . rend i False ts
      "{"      :ts -> onNewLine i     p . showChar   '{'  . new (i+1) ts
      "}" : ";":ts -> onNewLine (i-1) p . showString "};" . new (i-1) ts
      "}"      :ts -> onNewLine (i-1) p . showChar   '}'  . new (i-1) ts
      [";"]        -> char ';'
      ";"      :ts -> char ';' . new i ts
      t  : ts@(s:_) | closingOrPunctuation s
                   -> pending . showString t . rend i False ts
      t        :ts -> pending . space t      . rend i False ts
      []           -> id
    where
    -- Output character after pending indentation.
    char :: Char -> ShowS
    char c = pending . showChar c

    -- Output pending indentation.
    pending :: ShowS
    pending = if p then indent i else id

  -- Indentation (spaces) for given indentation level.
  indent :: Int -> ShowS
  indent i = replicateS (2*i) (showChar ' ')

  -- Continue rendering in new line with new indentation.
  new :: Int -> [String] -> ShowS
  new j ts = showChar '\n' . rend j True ts

  -- Make sure we are on a fresh line.
  onNewLine :: Int -> Bool -> ShowS
  onNewLine i p = (if p then id else showChar '\n') . indent i

  -- Separate given string from following text by a space (if needed).
  space :: String -> ShowS
  space t s =
    case (all isSpace t, null spc, null rest) of
      (True , _   , True ) -> []             -- remove trailing space
      (False, _   , True ) -> t              -- remove trailing space
      (False, True, False) -> t ++ ' ' : s   -- add space if none
      _                    -> t ++ s
    where
      (spc, rest) = span isSpace s

  closingOrPunctuation :: String -> Bool
  closingOrPunctuation [c] = c `elem` closerOrPunct
  closingOrPunctuation _   = False

  closerOrPunct :: String
  closerOrPunct = ")],;"

parenth :: Doc -> Doc
parenth ss = doc (showChar '(') . ss . doc (showChar ')')

concatS :: [ShowS] -> ShowS
concatS = foldr (.) id

concatD :: [Doc] -> Doc
concatD = foldr (.) id

replicateS :: Int -> ShowS -> ShowS
replicateS n f = concatS (replicate n f)

-- | The printer class does the job.

class Print a where
  prt :: Int -> a -> Doc

instance {-# OVERLAPPABLE #-} Print a => Print [a] where
  prt i = concatD . map (prt i)

instance Print Char where
  prt _ c = doc (showChar '\'' . mkEsc '\'' c . showChar '\'')

instance Print String where
  prt _ = printString

printString :: String -> Doc
printString s = doc (showChar '"' . concatS (map (mkEsc '"') s) . showChar '"')

mkEsc :: Char -> Char -> ShowS
mkEsc q = \case
  s | s == q -> showChar '\\' . showChar s
  '\\' -> showString "\\\\"
  '\n' -> showString "\\n"
  '\t' -> showString "\\t"
  s -> showChar s

prPrec :: Int -> Int -> Doc -> Doc
prPrec i j = if j < i then parenth else id

instance Print Integer where
  prt _ x = doc (shows x)

instance Print Double where
  prt _ x = doc (shows x)

instance Print Language.EO.Phi.Syntax.Abs.Bytes where
  prt _ (Language.EO.Phi.Syntax.Abs.Bytes i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.Function where
  prt _ (Language.EO.Phi.Syntax.Abs.Function i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.LabelId where
  prt _ (Language.EO.Phi.Syntax.Abs.LabelId i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.AlphaIndex where
  prt _ (Language.EO.Phi.Syntax.Abs.AlphaIndex i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.LabelMetaId where
  prt _ (Language.EO.Phi.Syntax.Abs.LabelMetaId i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.TailMetaId where
  prt _ (Language.EO.Phi.Syntax.Abs.TailMetaId i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.BindingsMetaId where
  prt _ (Language.EO.Phi.Syntax.Abs.BindingsMetaId i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.ObjectMetaId where
  prt _ (Language.EO.Phi.Syntax.Abs.ObjectMetaId i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.BytesMetaId where
  prt _ (Language.EO.Phi.Syntax.Abs.BytesMetaId i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.MetaFunctionName where
  prt _ (Language.EO.Phi.Syntax.Abs.MetaFunctionName i) = doc $ showString i
instance Print Language.EO.Phi.Syntax.Abs.Program where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.Program bindings -> prPrec i 0 (concatD [doc (showString "{"), doc (showString "\10214"), prt 0 bindings, doc (showString "\10215"), doc (showString "}")])

instance Print Language.EO.Phi.Syntax.Abs.MetaId where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.MetaIdLabel labelmetaid -> prPrec i 0 (concatD [prt 0 labelmetaid])
    Language.EO.Phi.Syntax.Abs.MetaIdTail tailmetaid -> prPrec i 0 (concatD [prt 0 tailmetaid])
    Language.EO.Phi.Syntax.Abs.MetaIdBindings bindingsmetaid -> prPrec i 0 (concatD [prt 0 bindingsmetaid])
    Language.EO.Phi.Syntax.Abs.MetaIdObject objectmetaid -> prPrec i 0 (concatD [prt 0 objectmetaid])
    Language.EO.Phi.Syntax.Abs.MetaIdBytes bytesmetaid -> prPrec i 0 (concatD [prt 0 bytesmetaid])

instance Print Language.EO.Phi.Syntax.Abs.Object where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.Formation bindings -> prPrec i 0 (concatD [doc (showString "\10214"), prt 0 bindings, doc (showString "\10215")])
    Language.EO.Phi.Syntax.Abs.Application object bindings -> prPrec i 0 (concatD [prt 0 object, doc (showString "("), prt 0 bindings, doc (showString ")")])
    Language.EO.Phi.Syntax.Abs.ObjectDispatch object attribute -> prPrec i 0 (concatD [prt 0 object, doc (showString "."), prt 0 attribute])
    Language.EO.Phi.Syntax.Abs.GlobalObject -> prPrec i 0 (concatD [doc (showString "\934")])
    Language.EO.Phi.Syntax.Abs.ThisObject -> prPrec i 0 (concatD [doc (showString "\958")])
    Language.EO.Phi.Syntax.Abs.Termination -> prPrec i 0 (concatD [doc (showString "\8869")])
    Language.EO.Phi.Syntax.Abs.MetaSubstThis object1 object2 -> prPrec i 0 (concatD [prt 0 object1, doc (showString "["), doc (showString "\958"), doc (showString "\8614"), prt 0 object2, doc (showString "]")])
    Language.EO.Phi.Syntax.Abs.MetaObject objectmetaid -> prPrec i 0 (concatD [prt 0 objectmetaid])
    Language.EO.Phi.Syntax.Abs.MetaTailContext object tailmetaid -> prPrec i 0 (concatD [prt 0 object, doc (showString "*"), prt 0 tailmetaid])
    Language.EO.Phi.Syntax.Abs.MetaFunction metafunctionname object -> prPrec i 0 (concatD [prt 0 metafunctionname, doc (showString "("), prt 0 object, doc (showString ")")])

instance Print Language.EO.Phi.Syntax.Abs.Binding where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.AlphaBinding attribute object -> prPrec i 0 (concatD [prt 0 attribute, doc (showString "\8614"), prt 0 object])
    Language.EO.Phi.Syntax.Abs.EmptyBinding attribute -> prPrec i 0 (concatD [prt 0 attribute, doc (showString "\8614"), doc (showString "\8709")])
    Language.EO.Phi.Syntax.Abs.DeltaBinding bytes -> prPrec i 0 (concatD [doc (showString "\916"), doc (showString "\10509"), prt 0 bytes])
    Language.EO.Phi.Syntax.Abs.DeltaEmptyBinding -> prPrec i 0 (concatD [doc (showString "\916"), doc (showString "\10509"), doc (showString "\8709")])
    Language.EO.Phi.Syntax.Abs.LambdaBinding function -> prPrec i 0 (concatD [doc (showString "\955"), doc (showString "\10509"), prt 0 function])
    Language.EO.Phi.Syntax.Abs.MetaBindings bindingsmetaid -> prPrec i 0 (concatD [prt 0 bindingsmetaid])
    Language.EO.Phi.Syntax.Abs.MetaDeltaBinding bytesmetaid -> prPrec i 0 (concatD [doc (showString "\916"), doc (showString "\10509"), prt 0 bytesmetaid])

instance Print [Language.EO.Phi.Syntax.Abs.Binding] where
  prt _ [] = concatD []
  prt _ [x] = concatD [prt 0 x]
  prt _ (x:xs) = concatD [prt 0 x, doc (showString ","), prt 0 xs]

instance Print Language.EO.Phi.Syntax.Abs.Attribute where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.Phi -> prPrec i 0 (concatD [doc (showString "\966")])
    Language.EO.Phi.Syntax.Abs.Rho -> prPrec i 0 (concatD [doc (showString "\961")])
    Language.EO.Phi.Syntax.Abs.Label labelid -> prPrec i 0 (concatD [prt 0 labelid])
    Language.EO.Phi.Syntax.Abs.Alpha alphaindex -> prPrec i 0 (concatD [prt 0 alphaindex])
    Language.EO.Phi.Syntax.Abs.MetaAttr labelmetaid -> prPrec i 0 (concatD [prt 0 labelmetaid])

instance Print Language.EO.Phi.Syntax.Abs.RuleAttribute where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.ObjectAttr attribute -> prPrec i 0 (concatD [prt 0 attribute])
    Language.EO.Phi.Syntax.Abs.DeltaAttr -> prPrec i 0 (concatD [doc (showString "\916")])
    Language.EO.Phi.Syntax.Abs.LambdaAttr -> prPrec i 0 (concatD [doc (showString "\955")])

instance Print Language.EO.Phi.Syntax.Abs.PeeledObject where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.PeeledObject objecthead objectactions -> prPrec i 0 (concatD [prt 0 objecthead, prt 0 objectactions])

instance Print Language.EO.Phi.Syntax.Abs.ObjectHead where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.HeadFormation bindings -> prPrec i 0 (concatD [doc (showString "\10214"), prt 0 bindings, doc (showString "\10215")])
    Language.EO.Phi.Syntax.Abs.HeadGlobal -> prPrec i 0 (concatD [doc (showString "\934")])
    Language.EO.Phi.Syntax.Abs.HeadThis -> prPrec i 0 (concatD [doc (showString "\958")])
    Language.EO.Phi.Syntax.Abs.HeadTermination -> prPrec i 0 (concatD [doc (showString "\8869")])

instance Print Language.EO.Phi.Syntax.Abs.ObjectAction where
  prt i = \case
    Language.EO.Phi.Syntax.Abs.ActionApplication bindings -> prPrec i 0 (concatD [doc (showString "("), prt 0 bindings, doc (showString ")")])
    Language.EO.Phi.Syntax.Abs.ActionDispatch attribute -> prPrec i 0 (concatD [doc (showString "."), prt 0 attribute])

instance Print [Language.EO.Phi.Syntax.Abs.ObjectAction] where
  prt _ [] = concatD []
  prt _ (x:xs) = concatD [prt 0 x, prt 0 xs]
