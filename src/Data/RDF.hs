-- |The Core module provides the fundamental types,
-- type classes, and functions of the library.
--

-- TODO: update writeT to writeTriple, etc.

module Data.RDF (
  -- * Parsing RDF
  RdfParser(parseString, parseFile, parseURL),
  -- * Serializing RDF
  RdfSerializer(hWriteRdf, writeRdf, hWriteH, writeH, hWriteTs, writeTs, hWriteT, writeT, hWriteN, writeN),
  -- * RDF type
  RDF(empty, mkRdf, triplesOf, select, query, baseUrl, prefixMappings, addPrefixMappings),
  -- * RDF triples, nodes, and literals
  Triple(Triple), triple, Triples, sortTriples,
  Node(UNode, BNode, BNodeGen, LNode),
  LValue(PlainL, PlainLL, TypedL),

  -- * Supporting types and functions
  BaseUrl(BaseUrl),
  PrefixMappings(PrefixMappings), toPMList, PrefixMapping(PrefixMapping),
  NodeSelector, isUNode, isBNode, isLNode,
  equalSubjects, equalPredicates, equalObjects,
  isIsomorphic,
  subjectOf, predicateOf, objectOf, isEmpty,
  rdfContainsNode,tripleContainsNode,
  listSubjectsWithPredicate,listObjectsOfPredicate,
  Subject, Predicate, Object,
  ParseFailure(ParseFailure),
  {- FastString(uniq,value),mkFastString, -}
  s2t,t2s,unode,bnode,lnode,plainL,plainLL,typedL,
  View, view,
  fromEither, removeDupes
)
where

import Data.RDF.Namespace
import Data.RDF.Utils ( s2t, t2s, canonicalize )
import qualified Data.Text as T
import Data.List
import System.IO
import Text.Printf

-- |A type class for ADTs that expose views to clients.
class View a b where
  view :: a -> b

-- |An alias for 'Node', defined for convenience and readability purposes.
type Subject = Node

-- |An alias for 'Node', defined for convenience and readability purposes.
type Predicate = Node

-- |An alias for 'Node', defined for convenience and readability purposes.
type Object = Node

-- |An RDF value is a set of (unique) RDF triples, together with the
-- operations defined upon them.
--
-- For information about the efficiency of the functions, see the
-- documentation for the particular RDF instance.
--
-- For more information about the concept of an RDF graph, see
-- the following: <http://www.w3.org/TR/rdf-concepts/#section-rdf-graph>.
class RDF rdf where

  -- |Return the base URL of this RDF, if any.
  baseUrl :: rdf -> Maybe BaseUrl

  -- |Return the prefix mappings defined for this RDF, if any.
  prefixMappings :: rdf -> PrefixMappings

  -- |Return an RDF with the specified prefix mappings merged with
  -- the existing mappings. If the Bool arg is True, then a new mapping
  -- for an existing prefix will replace the old mapping; otherwise,
  -- the new mapping is ignored.
  addPrefixMappings :: rdf -> PrefixMappings -> Bool -> rdf

  -- |Return an empty RDF.
  empty  :: rdf

  -- |Return a RDF containing all the given triples. Handling of duplicates
  -- in the input depend on the particular RDF implementation.
  mkRdf :: Triples -> Maybe BaseUrl -> PrefixMappings -> rdf

  -- |Return all triples in the RDF, as a list.
  triplesOf :: rdf -> Triples

  -- |Select the triples in the RDF that match the given selectors.
  --
  -- The three NodeSelector parameters are optional functions that match
  -- the respective subject, predicate, and object of a triple. The triples
  -- returned are those in the given graph for which the first selector
  -- returns true when called on the subject, the second selector returns
  -- true when called on the predicate, and the third selector returns true
  -- when called on the ojbect. A 'Nothing' parameter is equivalent to a
  -- function that always returns true for the appropriate node; but
  -- implementations may be able to much more efficiently answer a select
  -- that involves a 'Nothing' parameter rather than an @(id True)@ parameter.
  --
  -- The following call illustrates the use of select, and would result in
  -- the selection of all and only the triples that have a blank node
  -- as subject and a literal node as object:
  --
  -- > select gr (Just isBNode) Nothing (Just isLNode)
  --
  -- Note: this function may be very slow; see the documentation for the
  -- particular RDF implementation for more information.
  select    :: rdf -> NodeSelector -> NodeSelector -> NodeSelector -> Triples

  -- |Return the triples in the RDF that match the given pattern, where
  -- the pattern (3 Maybe Node parameters) is interpreted as a triple pattern.
  --
  -- The @Maybe Node@ params are interpreted as the subject, predicate, and
  -- object of a triple, respectively. @Just n@ is true iff the triple has
  -- a node equal to @n@ in the appropriate location; @Nothing@ is always
  -- true, regardless of the node in the appropriate location.
  --
  -- For example, @ query rdf (Just n1) Nothing (Just n2) @ would return all
  -- and only the triples that have @n1@ as subject and @n2@ as object,
  -- regardless of the predicate of the triple.
  query         :: rdf -> Maybe Node -> Maybe Node -> Maybe Node -> Triples

-- |An RdfParser is a parser that knows how to parse 1 format of RDF and
-- can parse an RDF document of that type from a string, a file, or a URL.
-- Required configuration options will vary from instance to instance.
class RdfParser p where

  -- |Parse RDF from the given bytestring, yielding a failure with error message or
  -- the resultant RDF.
  parseString :: forall rdf. (RDF rdf) => p -> T.Text -> Either ParseFailure rdf

  -- |Parse RDF from the local file with the given path, yielding a failure with error
  -- message or the resultant RDF in the IO monad.
  parseFile   :: forall rdf. (RDF rdf) => p -> String     -> IO (Either ParseFailure rdf)

  -- |Parse RDF from the remote file with the given HTTP URL (https is not supported),
  -- yielding a failure with error message or the resultant graph in the IO monad.
  parseURL    :: forall rdf. (RDF rdf) => p -> String -> IO (Either ParseFailure rdf)

-- |An RdfSerializer is a serializer of RDF to some particular output format, such as
-- NTriples or Turtle.
class RdfSerializer s where
  -- |Write the RDF to a file handle using whatever configuration is specified by
  -- the first argument.
  hWriteRdf     :: forall rdf. (RDF rdf) => s -> Handle -> rdf -> IO ()

  -- |Write the RDF to stdout; equivalent to @'hWriteRdf' stdout@.
  writeRdf      :: forall rdf. (RDF rdf) => s -> rdf -> IO ()

  -- |Write to the file handle whatever header information is required based on
  -- the output format. For example, if serializing to Turtle, this method would
  -- write the necessary \@prefix declarations and possibly a \@baseUrl declaration,
  -- whereas for NTriples, there is no header section at all, so this would be a no-op.
  hWriteH     :: forall rdf. (RDF rdf) => s -> Handle -> rdf -> IO ()

  -- |Write header information to stdout; equivalent to @'hWriteRdf' stdout@.
  writeH      :: forall rdf. (RDF rdf) => s -> rdf -> IO ()

  -- |Write some triples to a file handle using whatever configuration is specified
  -- by the first argument. 
  -- 
  -- WARNING: if the serialization format has header-level information 
  -- that should be output (e.g., \@prefix declarations for Turtle), then you should
  -- use 'hWriteG' instead of this method unless you're sure this is safe to use, since
  -- otherwise the resultant document will be missing the header information and 
  -- will not be valid.
  hWriteTs    :: s -> Handle  -> Triples -> IO ()

  -- |Write some triples to stdout; equivalent to @'hWriteTs' stdout@.
  writeTs     :: s -> Triples -> IO ()

  -- |Write a single triple to the file handle using whatever configuration is 
  -- specified by the first argument. The same WARNING applies as to 'hWriteTs'.
  hWriteT     :: s -> Handle  -> Triple  -> IO ()

  -- |Write a single triple to stdout; equivalent to @'hWriteT' stdout@.
  writeT      :: s -> Triple  -> IO ()

  -- |Write a single node to the file handle using whatever configuration is 
  -- specified by the first argument. The same WARNING applies as to 'hWriteTs'.
  hWriteN     :: s -> Handle  -> Node    -> IO ()

  -- |Write a single node to sdout; equivalent to @'hWriteN' stdout@.
  writeN      :: s -> Node    -> IO ()

-- |An RDF node, which may be either a URIRef node ('UNode'), a blank
-- node ('BNode'), or a literal node ('LNode').
data Node =

  -- |An RDF URI reference. See
  -- <http://www.w3.org/TR/rdf-concepts/#section-Graph-URIref> for more
  -- information.
  UNode !T.Text

  -- |An RDF blank node. See
  -- <http://www.w3.org/TR/rdf-concepts/#section-blank-nodes> for more
  -- information.
  | BNode !T.Text

  -- |An RDF blank node with an auto-generated identifier, as used in
  -- Turtle.
  | BNodeGen !Int

  -- |An RDF literal. See
  -- <http://www.w3.org/TR/rdf-concepts/#section-Graph-Literal> for more
  -- information.
  | LNode !LValue

-- ==============================
-- Constructor functions for Node

-- |Return a URIRef node for the given bytetring URI.
{-# INLINE unode #-}
unode :: T.Text -> Node
unode = UNode

-- |Return a blank node using the given string identifier.
{-# INLINE bnode #-}
bnode :: T.Text ->  Node
bnode = BNode

-- |Return a literal node using the given LValue.
{-# INLINE lnode #-}
lnode :: LValue ->  Node
lnode = LNode

-- Constructor functions for Node
-- ==============================


-- |A list of triples. This is defined for convenience and readability.
type Triples = [Triple]

-- |An RDF triple is a statement consisting of a subject, predicate,
-- and object, respectively.
--
-- See <http://www.w3.org/TR/rdf-concepts/#section-triples> for
-- more information.
data Triple = Triple !Node !Node !Node

-- |A smart constructor function for 'Triple' that verifies the node arguments
-- are of the correct type and creates the new 'Triple' if so or calls 'error'.
-- /subj/ must be a 'UNode' or 'BNode', and /pred/ must be a 'UNode'.
triple :: Subject -> Predicate -> Object -> Triple
triple subj pred obj
  | isLNode subj     =  error $ "subject must be UNode or BNode: "     ++ show subj
  | isLNode pred     =  error $ "predicate must be UNode, not LNode: " ++ show pred
  | isBNode pred     =  error $ "predicate must be UNode, not BNode: " ++ show pred
  | otherwise        =  Triple subj pred obj

-- |The actual value of an RDF literal, represented as the 'LValue'
-- parameter of an 'LNode'.
data LValue =
  -- Constructors are not exported, because we need to have more
  -- control over the format of the literal bytestring that we store.

  -- |A plain (untyped) literal value in an unspecified language.
  PlainL !T.Text

  -- |A plain (untyped) literal value with a language specifier.
  | PlainLL !T.Text !T.Text

  -- |A typed literal value consisting of the literal value and
  -- the URI of the datatype of the value, respectively.
  | TypedL !T.Text  !T.Text

-- ================================
-- Constructor functions for LValue

-- |Return a PlainL LValue for the given string value.
{-# INLINE plainL #-}
plainL :: T.Text -> LValue
plainL =  PlainL

-- |Return a PlainLL LValue for the given string value and language,
-- respectively.
{-# INLINE plainLL #-}
plainLL :: T.Text -> T.Text -> LValue
plainLL = PlainLL

-- |Return a TypedL LValue for the given string value and datatype URI,
-- respectively.
{-# INLINE typedL #-}
typedL :: T.Text -> T.Text -> LValue
typedL val dtype = TypedL (canonicalize dtype val) dtype

-- Constructor functions for LValue
-- ================================


-- |The base URL of an RDF.
newtype BaseUrl = BaseUrl T.Text
  deriving (Eq, Ord, Show)

-- |A 'NodeSelector' is either a function that returns 'True'
--  or 'False' for a node, or Nothing, which indicates that all
-- nodes would return 'True'.
--
-- The selector is said to select, or match, the nodes for
-- which it returns 'True'.
--
-- When used in conjunction with the 'select' method of 'Graph', three
-- node selectors are used to match a triple.
type NodeSelector = Maybe (Node -> Bool)

-- |Represents a failure in parsing an N-Triples document, including
-- an error message with information about the cause for the failure.
newtype ParseFailure = ParseFailure String
  deriving (Eq, Show)

-- |A node is equal to another node if they are both the same type
-- of node and if the field values are equal.
instance Eq Node where
  (UNode bs1)    ==  (UNode bs2)     =   bs1 ==  bs2
  (BNode bs1)    ==  (BNode bs2)     =   bs1 ==  bs2
  (BNodeGen i1)  ==  (BNodeGen i2)   =  i1 == i2
  (LNode l1)     ==  (LNode l2)      =  l1 == l2
  _              ==  _               =  False

-- |Node ordering is defined first by type, with Unode < BNode < BNodeGen
-- < LNode PlainL < LNode PlainLL < LNode TypedL, and secondly by
-- the natural ordering of the node value.
--
-- E.g., a '(UNode _)' is LT any other type of node, and a
-- '(LNode (TypedL _ _))' is GT any other type of node, and the ordering
-- of '(BNodeGen 44)' and '(BNodeGen 3)' is that of the values, or
-- 'compare 44 3', GT.
instance Ord Node where
  compare = compareNode

compareNode :: Node -> Node -> Ordering
compareNode (UNode bs1)                      (UNode bs2)                      = compare bs1 bs2
compareNode (UNode _)                        _                                = LT
compareNode (BNode bs1)                      (BNode bs2)                      = compare bs1 bs2
compareNode (BNode _)                        (UNode _)                        = GT
compareNode (BNode _)                        _                                = LT
compareNode (BNodeGen i1)                    (BNodeGen i2)                    = compare i1 i2
compareNode (BNodeGen _)                     (LNode _)                        = LT
compareNode (BNodeGen _)                     _                                = GT
compareNode (LNode (PlainL bs1))             (LNode (PlainL bs2))             = compare bs1 bs2
compareNode (LNode (PlainL _))               (LNode _)                        = LT
compareNode (LNode (PlainLL bs1 bs1'))       (LNode (PlainLL bs2 bs2'))       =
  case compare bs1' bs2' of
    EQ -> compare bs1 bs2
    LT -> LT
    GT -> GT
compareNode (LNode (PlainLL _ _))            (LNode (PlainL _))               = GT
compareNode (LNode (PlainLL _ _))            (LNode _)                        = LT
compareNode (LNode (TypedL bsType1 bs1))         (LNode (TypedL bsType2 bs2))         =
  case compare bs1 bs2 of
    EQ -> compare bsType1 bsType2
    LT -> LT
    GT -> GT
compareNode (LNode (TypedL _ _))             (LNode _)                        = GT
compareNode (LNode _)                        _                                = GT

-- |Two triples are equal iff their respective subjects, predicates, and objects
-- are equal.
instance Eq Triple where
  (Triple s1 p1 o1) == (Triple s2 p2 o2) = s1 == s2 && p1 == p2 && o1 == o2

-- |The ordering of triples is based on that of the subject, predicate, and object
-- of the triple, in that order.
instance Ord Triple where
  (Triple s1 p1 o1) `compare` (Triple s2 p2 o2) =
    case compareNode s1 s2 of
      EQ -> case compareNode p1 p2 of
              EQ -> compareNode o1 o2
              LT -> LT
              GT -> GT
      GT -> GT
      LT -> LT

-- |Two 'LValue' values are equal iff they are of the same type and all fields are
-- equal.
instance Eq LValue where
  (PlainL bs1)        ==  (PlainL bs2)        =  bs1 == bs2
  (PlainLL bs1 bs1')  ==  (PlainLL bs2 bs2')  =  bs1' == bs2'    &&  bs1 == bs2
  (TypedL bsType1 bs1)    ==  (TypedL bsType2 bs2)    =  bsType1 == bsType2 &&  bs1 == bs2
  _                   ==  _                   =  False

-- |Ordering of 'LValue' values is as follows: (PlainL _) < (PlainLL _ _)
-- < (TypedL _ _), and values of the same type are ordered by field values,
-- with '(PlainLL literalValue language)' being ordered by language first and
-- literal value second, and '(TypedL literalValue datatypeUri)' being ordered
-- by datatype first and literal value second.
instance Ord LValue where
  compare = compareLValue

{-# INLINE compareLValue #-}
compareLValue :: LValue -> LValue -> Ordering
compareLValue (PlainL bs1)       (PlainL bs2)       = compare bs1 bs2
compareLValue (PlainL _)         _                  = LT
compareLValue _                  (PlainL _)         = GT
compareLValue (PlainLL bs1 bs1') (PlainLL bs2 bs2') =
  case compare bs1' bs2' of
    EQ -> compare bs1 bs2
    GT -> GT
    LT -> LT
compareLValue (PlainLL _ _)       _                 = LT
compareLValue _                   (PlainLL _ _)     = GT
compareLValue (TypedL l1 t1) (TypedL l2 t2) =
  case compare t1 t2 of
    EQ -> compare l1 l2
    GT -> GT
    LT -> LT

-- String representations of the various data types; generally NTriples-like.

instance Show Triple where
  show (Triple s p o) =
    printf "Triple(%s,%s,%s)" (show s) (show p) (show o)

instance Show Node where
  show (UNode uri)                   = "UNode(" ++ show uri ++ ")"
  show (BNode  i)                    = "BNode(" ++ show i ++ ")"
  show (BNodeGen genId)              = "BNodeGen(" ++ show genId ++ ")"
  show (LNode lvalue)                = "LNode(" ++ show lvalue ++ ")"

instance Show LValue where
  show (PlainL lit)               = "PlainL(" ++ T.unpack lit ++ ")"
  show (PlainLL lit lang)         = "PlainLL(" ++ T.unpack lit ++ ", " ++ T.unpack lang ++ ")"
  show (TypedL lit dtype)         = "TypedL(" ++ T.unpack lit ++ "," ++ show dtype ++ ")"

-- |Answer the given list of triples in sorted order.
sortTriples :: Triples -> Triples
sortTriples = sort

-- |Answer the subject node of the triple.
{-# INLINE subjectOf #-}
subjectOf :: Triple -> Node
subjectOf (Triple s _ _) = s

-- |Answer the predicate node of the triple.
{-# INLINE predicateOf #-}
predicateOf :: Triple -> Node
predicateOf (Triple _ p _) = p

-- |Answer the object node of the triple.
{-# INLINE objectOf #-}
objectOf :: Triple -> Node
objectOf (Triple _ _ o)   = o

-- |Answer if rdf contains node.
rdfContainsNode :: forall rdf. (RDF rdf) => rdf -> Node -> Bool
rdfContainsNode rdf node =
  let ts = triplesOf rdf
      xs = map (tripleContainsNode node) ts
  in elem True xs

-- |Answer if triple contains node.
tripleContainsNode :: Node -> Triple -> Bool
{-# INLINE tripleContainsNode #-}
tripleContainsNode node t = 
 subjectOf t == node || predicateOf t == node || objectOf t == node

-- |Answer if given node is a URI Ref node.
{-# INLINE isUNode #-}
isUNode :: Node -> Bool
isUNode (UNode _) = True
isUNode _         = False

-- |Answer if given node is a blank node.
{-# INLINE isBNode #-}
isBNode :: Node -> Bool
isBNode (BNode _)    = True
isBNode (BNodeGen _) = True
isBNode _            = False

-- |Answer if given node is a literal node.
{-# INLINE isLNode #-}
isLNode :: Node -> Bool
isLNode (LNode _) = True
isLNode _         = False

-- |Determine whether two triples have equal subjects.
equalSubjects :: Triple -> Triple -> Bool
equalSubjects (Triple s1 _ _) (Triple s2 _ _) = s1 == s2

-- |Determine whether two triples have equal predicates.
equalPredicates :: Triple -> Triple -> Bool
equalPredicates (Triple _ p1 _) (Triple _ p2 _) = p1 == p2

-- |Determine whether two triples have equal objects.
equalObjects :: Triple -> Triple -> Bool
equalObjects (Triple _ _ o1) (Triple _ _ o2) = o1 == o2

-- |Determines whether the 'RDF' contains zero triples.
isEmpty :: RDF rdf => rdf -> Bool
isEmpty rdf =
  let ts = triplesOf rdf
  in null ts

-- |Lists of all subjects of triples with the given predicate.
listSubjectsWithPredicate :: RDF rdf => rdf -> Predicate -> [Subject]
listSubjectsWithPredicate rdf pred =
  listNodesWithPredicate rdf pred subjectOf

-- |Lists of all objects of triples with the given predicate.
listObjectsOfPredicate :: RDF rdf => rdf -> Predicate -> [Object]
listObjectsOfPredicate rdf pred =
  listNodesWithPredicate rdf pred objectOf

listNodesWithPredicate :: RDF rdf => rdf -> Predicate -> (Triple -> Node) -> [Node]
listNodesWithPredicate rdf pred f =
  let ts = triplesOf rdf
      xs = filter (\t -> predicateOf t == pred) ts
  in map f xs


-- |Convert a parse result into an RDF if it was successful
-- and error and terminate if not.
fromEither :: RDF rdf => Either ParseFailure rdf -> rdf
fromEither res =
  case res of
    (Left err) -> error (show err)
    (Right rdf) -> rdf

-- |Remove duplicate triples, returning unique triples. This 
-- function may return the triples in a different order than 
-- given.
removeDupes :: Triples -> Triples
removeDupes =  map head . group . sort

-- |This determines if two RDF representations are equal regardless of blank
-- node names, triple order and prefixes.  In math terms, this is the \simeq
-- latex operator, or ~=
isIsomorphic :: forall rdf1 rdf2. (RDF rdf1, RDF rdf2) => rdf1 -> rdf2 -> Bool
isIsomorphic g1 g2 = normalize g1 == normalize g2
  where normalize :: forall rdf. (RDF rdf) => rdf -> Triples
        normalize = sort . nub . expandTriples

-- |Expand the triples in a graph with the prefix map and base URL for that
-- graph.
expandTriples :: (RDF rdf) => rdf -> Triples
expandTriples rdf = expandTriples' [] (baseUrl rdf) (prefixMappings rdf) (triplesOf rdf)

expandTriples' :: Triples -> Maybe BaseUrl -> PrefixMappings -> Triples -> Triples
expandTriples' acc _ _ [] = acc
expandTriples' acc baseUrl prefixMappings (t:rest) = expandTriples' (normalize baseUrl prefixMappings t : acc) baseUrl prefixMappings rest
  where normalize baseUrl prefixMappings = expandPrefixes prefixMappings . expandBaseUrl baseUrl
        expandBaseUrl (Just _) triple = triple
        expandBaseUrl Nothing triple = triple
        expandPrefixes _ triple = triple
