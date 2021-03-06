{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE TupleSections         #-}

module Main ( main ) where

import           Aura.Pkgbuild.Fetch (getPkgbuild)
import           Aura.Pkgbuild.Security (bannedTerms, parsedPB)
import           Aura.Types
import           BasePrelude
import           Control.Compactable (fmapEither)
import           Control.Concurrent.Async (mapConcurrently)
import           Control.Error.Util (note)
import           Data.List.Split (chunksOf)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           Language.Bash.Pretty (prettyText)
import           Network.HTTP.Client (newManager)
import           Network.HTTP.Client.TLS (tlsManagerSettings)
import           Text.Pretty.Simple (pPrintNoColor)

---

main :: IO ()
main = do
  m   <- newManager tlsManagerSettings
  pns <- sort . map PkgName . T.lines <$> T.readFile "aur-security/packages.txt"
  let !len = length pns
  putStrLn $ printf "Read %d package names." len
  q <- mapConcurrently (traverse (\pn -> fmap (pn,) . note pn <$> getPkgbuild m pn)) $ chunksOf (len `div` 16) pns
  let (nopbs, pbs) = partitionEithers $ fold q
  unless (null nopbs) . putStrLn $ printf "PKGBUILDs couldn't be found for %d packages." (length nopbs)
  putStrLn "Analysing legal packages..."
  let (unparsed, parsed) = fmapEither f pbs
  unless (null unparsed) $ do
    putStrLn $ printf "The PKGBUILDs of %d packages couldn't be parsed. They were:" (length unparsed)
    traverse_ print unparsed
  let !bads = mapMaybe g parsed
  unless (null bads) $ do
    putStrLn $ printf "%d PKGBUILDs contained banned bash terms. They were:" (length bads)
    traverse_ pPrintNoColor bads
  putStrLn "Done."
    where f pair@(pn, _) = note pn $ traverse parsedPB pair
          g = traverse (maybeList . map (first prettyText) . bannedTerms)

maybeList :: [a] -> Maybe [a]
maybeList [] = Nothing
maybeList xs = Just xs
