-- A program for generating a Gentoo ebuild from a .cabal file
--
-- Author : Duncan Coutts <dcoutts@gentoo.org>
--
-- Created: 21 July 2005
--
-- Copyright (C) 2005 Duncan Coutts
--
-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- General Public License for more details.
--
module Cabal2Ebuild
        (cabal2ebuild
        ,convertDependencies
        ,convertDependency) where

import qualified Distribution.PackageDescription as Cabal
                                                (PackageDescription(..))
import qualified Distribution.Package as Cabal  (PackageIdentifier(..)
                                                , Dependency(..))
import qualified Distribution.Version as Cabal  (VersionRange, foldVersionRange')
import Distribution.Text (display)

import Data.Char          (isUpper)
import Data.Maybe

import Portage.Dependency
import qualified Portage.Cabal as Portage
import qualified Portage.PackageId as Portage
import qualified Portage.EBuild as Portage
import qualified Portage.EBuild.CabalFeature as Portage
import qualified Portage.Resolve as Portage
import qualified Portage.EBuild as E
import qualified Portage.Overlay as O
import Portage.Version

cabal2ebuild :: Portage.Category -> Cabal.PackageDescription -> Portage.EBuild
cabal2ebuild cat pkg = Portage.ebuildTemplate {
    E.name        = Portage.cabal_pn_to_PN cabal_pn,
    E.category    = display cat,
    E.hackage_name= cabalPkgName,
    E.version     = display (Cabal.pkgVersion (Cabal.package pkg)),
    E.description = if null (Cabal.synopsis pkg) then Cabal.description pkg
                                               else Cabal.synopsis pkg,
    E.long_desc       = if null (Cabal.description pkg) then Cabal.synopsis pkg
                                               else Cabal.description pkg,
    E.homepage        = thisHomepage,
    E.license         = Portage.convertLicense $ Cabal.license pkg,
    E.slot            = (E.slot E.ebuildTemplate) ++ (if hasLibs then "/${PV}" else ""),
    E.my_pn           = if any isUpper cabalPkgName then Just cabalPkgName else Nothing,
    E.features        = E.features E.ebuildTemplate
                   ++ (if hasLibs then ([ Portage.Lib
                                        , Portage.Profile
                                        , Portage.Haddock
                                        , Portage.Hoogle
                                        ]
                                        ++ if cabalPkgName == "hscolour"
                                                then []
                                                else [Portage.HsColour])
                                  else [])
                   ++ (if hasTests then [Portage.TestSuite]
                                   else [])
  } where
        cabal_pn = Cabal.pkgName $ Cabal.package pkg
        cabalPkgName = display cabal_pn
        hasLibs = isJust (Cabal.library pkg)
        hasTests = (not . null) (Cabal.testSuites pkg)
        thisHomepage = if (null $ Cabal.homepage pkg)
                         then E.homepage E.ebuildTemplate
                         else Cabal.homepage pkg

convertDependencies :: O.Overlay -> Portage.Category -> [Cabal.Dependency] -> [Dependency]
convertDependencies overlay category = map (convertDependency overlay category)

convertDependency :: O.Overlay -> Portage.Category -> Cabal.Dependency -> Dependency
convertDependency overlay category (Cabal.Dependency pname versionRange)
  = convert versionRange
  where
    pn = case Portage.resolveFullPortageName overlay pname of
            Just r  -> r
            Nothing -> Portage.PackageName category (Portage.normalizeCabalPackageName pname)
    mk_p :: DRange -> Dependency
    mk_p dr = DependAtom (Atom pn dr (DAttr AnySlot []))
    p_v v   = fromCabalVersion v

    convert :: Cabal.VersionRange -> Dependency
    convert =  Cabal.foldVersionRange'
             (          mk_p (DRange ZeroB                 InfinityB)          -- ^ @\"-any\"@ version
            )(\v     -> mk_p (DExact (p_v v))                                  -- ^ @\"== v\"@
            )(\v     -> mk_p (DRange (StrictLB (p_v v))    InfinityB)          -- ^ @\"> v\"@
            )(\v     -> mk_p (DRange ZeroB                 (StrictUB (p_v v))) -- ^ @\"< v\"@
            )(\v     -> mk_p (DRange (NonstrictLB (p_v v)) InfinityB)         -- ^ @\">= v\"@
            )(\v     -> mk_p (DRange ZeroB                (NonstrictUB (p_v v))) -- ^ @\"<= v\"@
            )(\v1 v2 -> mk_p (DRange (NonstrictLB (p_v v1)) (StrictUB (p_v v2))) -- ^ @\"== v.*\"@ wildcard. (incl lower, excl upper)
            )(\v1 v2 -> mk_p (DRange (NonstrictLB (p_v v1)) (StrictUB (p_v v2))) -- ^ @\"^>= v\"@ major upper bound
            )(\g1 g2 -> DependAnyOf [g1, g2]                                  -- ^ @\"_ || _\"@ union
            )(\r1 r2 -> DependAllOf [r1, r2]                                  -- ^ @\"_ && _\"@ intersection
            )(\dp    -> dp                                                    -- ^ @\"(_)\"@ parentheses
            )
