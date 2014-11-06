module Opaleye.Internal.SqlOpaleye where

import           Prelude hiding (product)

import qualified Opaleye.Internal.PrimQuery as PQ
import qualified Opaleye.Internal.NEList as NE
import qualified Opaleye.Internal.Sql as Old

import qualified Database.HaskellDB.PrimQuery as HP
import qualified Database.HaskellDB.Sql as S
import qualified Database.HaskellDB.Sql.Print as PP
import qualified Database.HaskellDB.Sql.Default as SD

import qualified Text.PrettyPrint.HughesPJ as HPJ
import           Text.PrettyPrint.HughesPJ (Doc, ($$), (<+>), text, empty)

import qualified Data.Maybe as M

sqlQueryGenerator :: PQ.PrimQueryFold Select
sqlQueryGenerator = (unit, baseTable, product, aggregate, order, limit_, leftJoin)

sql :: (PQ.PrimQuery, [HP.PrimExpr]) -> Select
sql (pq, pes) = SelectFrom $ newSelect { attrs = makeAttrs pes
                                       , tables = [pqSelect] }
  where pqSelect = PQ.foldPrimQuery sqlQueryGenerator pq
        makeAttrs = flip (zipWith makeAttr) [1..]
        makeAttr pe i = (Old.sqlExpr pe, Just ("result" ++ show (i :: Int)))

unit :: Select
unit = SelectFrom newSelect { attrs  = [(S.ConstSqlExpr "0", Nothing)] }

baseTable :: String -> [(PQ.Symbol, String)] -> Select
baseTable name columns = SelectFrom $
    newSelect { attrs = map (\(sym, col) -> (S.ColumnSqlExpr col, Just sym)) columns
              , tables = [Table name] }

product :: NE.NEList Select -> [HP.PrimExpr] -> Select
product ss pes = SelectFrom $
    newSelect { tables = NE.toList ss
              , criteria = map Old.sqlExpr pes }

aggregate :: [(Maybe (PQ.Symbol, HP.AggrOp), HP.PrimExpr)] -> Select -> Select
aggregate aggrs s = SelectFrom $ newSelect { attrs = map attr aggrs
                                           , tables = [s]
                                           , groupBy = groupBy' }
  where groupBy' = (map Old.sqlExpr
                    . map (\(_, _, e) -> e)
                    . filter (\(_, x, _) -> M.isNothing x)) aggrs
        attr (x, aggrOp, pe) = (Old.sqlExpr (Old.aggrExpr aggrOp pe), Just x)

order :: [HP.OrderExpr] -> Select -> Select
order oes s = SelectFrom $
    newSelect { tables = [s]
              , orderBy = map (SD.toSqlOrder SD.defaultSqlGenerator) oes }

limit_ :: PQ.LimitOp -> Select -> Select
limit_ lo s = SelectFrom $ newSelect { tables = [s]
                                     , limit = limit'
                                     , offset = offset' }
  where (limit', offset') = case lo of
          PQ.LimitOp n         -> (Just n, Nothing)
          PQ.OffsetOp n        -> (Nothing, Just n)
          PQ.LimitOffsetOp l o -> (Just l, Just o)

leftJoin :: [(Symbol, PQ.PrimExpr)] -> PQ.PrimExpr -> Select -> Select -> Select
leftJoin 

newSelect :: From Select
newSelect = From {
  attrs     = [],
  tables    = [],
  criteria  = [],
  groupBy   = [],
  orderBy   = [],
  limit     = Nothing,
  offset    = Nothing
  }

--

data Distinct = Distinct

data TableName = String

data From s = From {
  attrs     :: [(S.SqlExpr, Maybe S.SqlColumn)],
  tables    :: [s],
  criteria  :: [S.SqlExpr],
  groupBy   :: [S.SqlExpr],
  orderBy   :: [(S.SqlExpr, S.SqlOrder)],
  limit     :: Maybe Int,
  offset    :: Maybe Int
  }
          deriving Show

data LeftJoin s = LeftJoin {
  attrs :: [(S.SqlExpr, Maybe S.SqlColumn)],
  left  :: s,
  right :: s,
  cond  :: S.SqlExpr
  }
                deriving Show

data Select = SelectFrom (From Select)
            | Table S.SqlTable
            | LeftJoin Select Select S.SqlExpr
            deriving Show

type SelectFold s = (From Select -> s, S.SqlTable -> s)

foldSelect :: SelectFold s -> Select -> s
foldSelect (selectFrom, table) = fold
  where fold (SelectFrom s) = selectFrom s
        fold (Table t)      = table t

ppSql :: Select -> Doc
ppSql (SelectFrom s) = ppSelectFrom s
ppSql (Table name) = text name

ppSelectFrom :: From Select -> Doc
ppSelectFrom s = text "SELECT"
                 <+> ppAttrs (attrs s)
                 $$  ppTables (tables s)
                 $$  PP.ppWhere (criteria s)
                 $$  ppGroupBy (groupBy s)
                 $$  PP.ppOrderBy (orderBy s)
                 $$  ppLimit (limit s)
                 $$  ppOffset (offset s)

ppAttrs :: [(S.SqlExpr, Maybe S.SqlColumn)] -> Doc
ppAttrs [] = text "*"
ppAttrs xs = PP.commaV nameAs xs

-- This is pretty much just nameAs from HaskellDB
nameAs :: (S.SqlExpr, Maybe S.SqlColumn) -> Doc
nameAs (expr, name) = PP.ppAs (M.fromMaybe "" name) (PP.ppSqlExpr expr)

ppTables :: [Select] -> Doc
ppTables [] = empty
ppTables ts = text "FROM" <+> PP.commaV ppTable (zipWith tableAlias [1..] ts)
  where tableAlias :: Int -> Select -> (S.SqlTable, Select)
        tableAlias i select = ("T" ++ show i, select)

ppTable :: (S.SqlTable, Select) -> Doc
ppTable (alias, select) = case select of
  Table name -> PP.ppAs alias (text name)
  SelectFrom selectFrom -> PP.ppAs alias (HPJ.parens (ppSelectFrom selectFrom))

ppGroupBy :: [S.SqlExpr] -> Doc
ppGroupBy [] = empty
ppGroupBy xs = (PP.ppGroupBy . S.Columns . map (\expr -> ("", expr))) xs

ppLimit :: Maybe Int -> Doc
ppLimit Nothing = empty
ppLimit (Just n) = text ("LIMIT " ++ show n)

ppOffset :: Maybe Int -> Doc
ppOffset Nothing = empty
ppOffset (Just n) = text ("OFFSET " ++ show n)