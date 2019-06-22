{ nixpkgs ? import ./dep/nixpkgs-overlayed.nix }:
(nixpkgs.pkgs.haskell.lib.addBuildTools (import ./. {}) 
  (with nixpkgs.pkgs ; [ 
    cabal-install
    haskellPackages.ghcid
  ])
).env
