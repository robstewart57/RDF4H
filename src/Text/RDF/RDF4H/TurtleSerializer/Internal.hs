module Text.RDF.RDF4H.TurtleSerializer.Internal
  ( findMapping
  , writeUNodeUri
  )
where

import           Data.List (elemIndex)
import qualified Data.Map as Map
import           Data.RDF.Namespace hiding (rdf)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           System.IO

-- |Converts an aliased URI (e.g., 'rdf:subject') to a tuple whose first element
-- is the full (non-aliased) URI and whose second element is the target/path
-- portion (the part after the colon in the aliased URI).
findMapping :: PrefixMappings -- ^The 'PrefixMappings' to be searched for the prefix that may be a part of the URI.
            -> T.Text         -- ^The URI.
            -> Maybe (T.Text, T.Text)
findMapping (PrefixMappings pms) aliasedURI = do
  (prefix, target) <- splitAliasedURI aliasedURI
  uri <- Map.lookup prefix pms
  pure (uri, target)

-- |Writes the given 'UNode' to the given 'Handle'.
writeUNodeUri :: Handle         -- ^The Handle to write to
              -> T.Text         -- ^The text from a UNode
              -> PrefixMappings -- ^The 'PrefixMappings' which should contain a mapping for any prefix found in the URI.
              -> IO ()
writeUNodeUri h uri pms =

  -- TODO: The following code determines if the URI text is a QName (see
  -- https://www.w3.org/2007/02/turtle/primer) by checking to see if a mapping
  -- for the QName's prefix exists in the given 'PrefixMappings'. If a mapping
  -- exists, then it is assumed to be a QName. The problem with this approach is
  -- that there may not be a mapping for the prefix in the given
  -- 'PrefixMappings' (this is a separate issue that should be addressed)
  -- leading this code to write the UNode with angle brackets when it should not
  -- have them.
  case mapping of
    Nothing -> hPutChar h '<' >> T.hPutStr h uri >> hPutChar h '>'
    _ -> T.hPutStr h uri
  where
    mapping = findMapping pms uri

-- |Given an aliased URI (e.g., 'rdf:subject') return a tuple whose first
-- element is the alias ('rdf') and whose second part is the path or fragment
-- ('subject').
splitAliasedURI :: T.Text  -- ^Aliased URI.
                -> Maybe (T.Text, T.Text)
splitAliasedURI uri = do
  let uriStr = T.unpack uri
  i <- elemIndex ':' uriStr
  let (prefix, target) = splitAt i uriStr
  pure (T.pack prefix, T.pack $ tail target)
