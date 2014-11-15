{-# LANGUAGE FlexibleContexts, FlexibleInstances, MultiParamTypeClasses #-}

module Opaleye.Internal.Join where

import qualified Opaleye.Internal.Tag as T
import qualified Opaleye.Internal.PackMap as PM
import           Opaleye.Column (Column, Nullable)
import qualified Opaleye.Column as C
import qualified Opaleye.Internal.Values as V

import           Data.Profunctor (Profunctor, dimap)
import           Data.Profunctor.Product (ProductProfunctor, empty, (***!))
import qualified Data.Profunctor.Product.Default as D

import qualified Database.HaskellDB.PrimQuery as HPQ

data NullMaker a b = NullMaker (a -> b)

toNullable :: NullMaker a b -> a -> b
toNullable (NullMaker f) = f

extractLeftJoinFields :: Int -> T.Tag -> HPQ.PrimExpr
            -> PM.PM [(String, HPQ.PrimExpr)] HPQ.PrimExpr
extractLeftJoinFields n = V.extractAttr (\i -> "result" ++ show n ++ "_" ++ i)

instance D.Default NullMaker (Column a) (Column (Nullable a)) where
  def = NullMaker C.unsafeCoerce

instance D.Default NullMaker (Column (Nullable a)) (Column (Nullable a)) where
  def = NullMaker C.unsafeCoerce

-- { Boilerplate instances

instance Profunctor NullMaker where
  dimap f g (NullMaker h) = NullMaker (dimap f g h)

instance ProductProfunctor NullMaker where
  empty = NullMaker empty
  NullMaker f ***! NullMaker f' = NullMaker (f ***! f')

--
