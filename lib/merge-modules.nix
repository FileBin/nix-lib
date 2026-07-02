{ pkgs, ... }:
modules:
let
  make-module = (import ./make-module.nix) { inherit pkgs; };
in builtins.foldl' (acc: x: acc // x) { } (map (x: (make-module x)) modules)
