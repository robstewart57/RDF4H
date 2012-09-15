module Main where

import Test.Framework (defaultMain)

import qualified Data.RDF.TriplesGraph_Test as TriplesGraph
import qualified Data.RDF.MGraph_Test as MGraph
import qualified Text.RDF.RDF4H.XmlParser_Test as XmlParser
import qualified Text.RDF.RDF4H.TurtleParser_ConformanceTest as TurtleParser

main :: IO () 
main = defaultMain (  TriplesGraph.tests
                   ++ MGraph.tests
                   ++ TurtleParser.tests
                   ++ XmlParser.tests
                   )

