{ pkgs, ... }:
dir:
let
  lib = pkgs.lib;

  modules = lib.collect lib.isString (
    lib.mapAttrsRecursive (path: type: lib.concatStringsSep "/" path) (builtins.readDir dir)
  );
in
map (file: dir + "/${file}") (
  lib.filter (file: file != "default.nix") modules
)
