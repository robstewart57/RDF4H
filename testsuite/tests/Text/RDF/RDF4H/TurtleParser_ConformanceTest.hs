module Text.RDF.RDF4H.TurtleParser_ConformanceTest where

-- Testing imports
import Test.Framework.Providers.API
import Test.Framework.Providers.HUnit
import qualified Test.HUnit as T

import Data.RDF
import Data.RDF.TriplesGraph
import Data.RDF.GraphTestUtils

import Text.RDF.RDF4H.TurtleParser
import Text.RDF.RDF4H.NTriplesParser

import Text.Printf
import Data.ByteString.Lazy.Char8(ByteString)
import qualified Data.ByteString.Lazy.Char8 as B


tests = [ testGroup "TurtleParser" allCTests ]


-- A list of other tests to run, each entry of which is (directory, fname_without_ext).
otherTestFiles = [("data/ttl", "example1"),
                  ("data/ttl", "example2"),
                  ("data/ttl", "example3"),
                  ("data/ttl", "example5"),
                  ("data/ttl", "example6"),
                  ("data/ttl", "example7"),
                  ("data/ttl", "fawlty1")
                 ]

-- The Base URI to be used for all conformance tests:
testBaseUri :: String
testBaseUri  = "http://www.w3.org/2001/sw/DataAccess/df1/tests/"

mtestBaseUri :: Maybe BaseUrl
mtestBaseUri = Just $ BaseUrl $ B.pack testBaseUri

fpath :: String -> Int -> String -> String
fpath name i ext = printf "data/ttl/conformance/%s-%02d.%s" name i ext :: String

allCTests :: [Test]
allCTests = ts1 ++ ts2 ++ ts3
   where
        ts1 = map (buildTest . checkGoodConformanceTest) [0..30]
        ts2 = map (buildTest . checkBadConformanceTest) [0..14]
        ts3 = map (buildTest . (uncurry checkGoodOtherTest)) otherTestFiles

checkGoodConformanceTest :: Int -> IO Test
checkGoodConformanceTest i =
  do
    expGr <- loadExpectedGraph "test" i
    inGr  <- loadInputGraph    "test" i
    doGoodConformanceTest expGr inGr (printf "test %d" i :: String)

checkGoodOtherTest :: String -> String -> IO Test
checkGoodOtherTest dir fname =
  do 
    expGr <- loadExpectedGraph1 (printf "%s/%s.out" dir fname :: String)
    inGr  <- loadInputGraph1 dir fname
    doGoodConformanceTest expGr inGr $ printf "test using file \"%s\"" fname

doGoodConformanceTest   :: Either ParseFailure TriplesGraph -> 
                           Either ParseFailure TriplesGraph -> 
                           String -> IO Test
doGoodConformanceTest expGr inGr testname =
  do
    t1 <-  return (return expGr >>= assertLoadSuccess (printf "expected (%s): " testname))
    t2 <-  return (return inGr  >>= assertLoadSuccess (printf "   input (%s): " testname))
    t3 <-  return $ assertEquivalent testname expGr inGr
    return $ testGroup (printf "Conformance %s" testname) $ map (\(name, assertion) -> testCase name assertion) [("Loading expected graph data", t1), ("Loading input graph data", t2), ("Comparing graphs", t3)]

checkBadConformanceTest :: Int -> IO Test
checkBadConformanceTest i =
  do
    t <- return (loadInputGraph "bad" i >>= assertLoadFailure (show i))
    return $ testCase (printf "Loading test %d (negative)" i) t

-- Determines if graphs are equivalent, returning Nothing if so or else a diagnostic message.
-- First graph is expected graph, second graph is actual.
equivalent :: RDF rdf => Either ParseFailure rdf -> Either ParseFailure rdf -> Maybe String
equivalent (Left _) _                = Nothing
equivalent _        (Left _)         = Nothing
equivalent (Right gr1) (Right gr2)   = (test $! zip gr1ts gr2ts)
  where
    gr1ts = uordered $ triplesOf $ gr1
    gr2ts = uordered $ triplesOf $ gr2
    test []           = Nothing
    test ((t1,t2):ts) =
      case compareTriple t1 t2 of
        Nothing -> test ts
        err     -> err
    compareTriple t1 t2 =
      if equalNodes s1 s2 && equalNodes p1 p2 && equalNodes o1 o2
        then Nothing
        else Just ("Expected:\n  " ++ show t1 ++ "\nFound:\n  " ++ show t2 ++ "\n")
      where
        (s1, p1, o1) = f t1
        (s2, p2, o2) = f t2
        f t = (subjectOf t, predicateOf t, objectOf t)
    equalNodes (BNode fs1) (BNodeGen i) = B.reverse (value fs1) == s2b ("_:genid" ++ show i)
    equalNodes n1          n2           = n1 == n2

-- Returns a graph for a good ttl test that is intended to pass, and normalizes
-- triples into a format so that they can be compared with the expected output triples.
loadInputGraph :: String -> Int -> IO (Either ParseFailure TriplesGraph)
loadInputGraph name n =
  B.readFile (fpath name n "ttl") >>=
    return . parseString (TurtleParser mtestBaseUri (mkDocUrl testBaseUri name n)) >>= return . handleLoad
loadInputGraph1 :: String -> String -> IO (Either ParseFailure TriplesGraph)
loadInputGraph1 dir fname =
  B.readFile (printf "%s/%s.ttl" dir fname :: String) >>=
    return . parseString (TurtleParser mtestBaseUri (mkDocUrl1 testBaseUri fname)) >>= return . handleLoad

handleLoad :: Either ParseFailure TriplesGraph -> Either ParseFailure TriplesGraph
handleLoad res =
  case res of
    l@(Left _)  -> l
    (Right gr)  -> Right $ mkRdf (map normalize (triplesOf gr)) (baseUrl gr) (prefixMappings gr)

normalize :: Triple -> Triple
normalize t = let s' = normalizeN $ subjectOf t
                  p' = normalizeN $ predicateOf t
                  o' = normalizeN $ objectOf t
              in  triple s' p' o'
normalizeN :: Node -> Node
normalizeN (BNodeGen i) = BNode $ mkFastString (s2b $ "_:genid" ++ show i)
normalizeN n            = n

loadExpectedGraph :: String -> Int -> IO (Either ParseFailure TriplesGraph)
loadExpectedGraph name n = loadExpectedGraph1 (fpath name n "out")
loadExpectedGraph1 :: String -> IO (Either ParseFailure TriplesGraph)
loadExpectedGraph1 filename = B.readFile filename >>= return . parseString NTriplesParser

assertLoadSuccess, assertLoadFailure :: String -> Either ParseFailure TriplesGraph -> T.Assertion
assertLoadSuccess idStr (Left (ParseFailure err)) = T.assertFailure $ idStr  ++ err
assertLoadSuccess _     (Right _) = return ()
assertLoadFailure _     (Left _)  = return ()
assertLoadFailure idStr _         = T.assertFailure $ "Bad test " ++ idStr ++ " loaded successfully."

assertEquivalent :: RDF rdf => String -> Either ParseFailure rdf -> Either ParseFailure rdf -> T.Assertion
assertEquivalent testname r1 r2 =
  case equiv of
    Nothing    -> T.assert True
    (Just msg) -> fail $ "Graph " ++ testname ++ " not equivalent to expected:\n" ++ msg
  where equiv = equivalent r1 r2

mkDocUrl :: String -> String -> Int -> Maybe ByteString
mkDocUrl baseDocUrl fname testNum = Just $ s2b $ printf "%s%s-%02d.ttl" baseDocUrl fname testNum

mkDocUrl1 :: String -> String -> Maybe ByteString
mkDocUrl1 baseDocUrl fname        = Just $ s2b $ printf "%s%s.ttl" baseDocUrl fname
