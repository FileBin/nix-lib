{ pkgs, ... }:
let
  list-modules = (import ../lib/list-modules.nix) { inherit pkgs; };
  make-simple-module = (import ../lib/make-simple-module.nix) { inherit pkgs; };

  lib = pkgs.lib;

  subdirectories = lib.filterAttrs (name: value: value == "directory") (builtins.readDir ./.);

  categories = lib.collect lib.isString (lib.mapAttrsRecursive (path: type: lib.concatStringsSep "/" path) subdirectories);

  simple-modules-builder = category: map (path: make-simple-module { inherit category path; }) (list-modules (./. + "/${category}"));
  simple-modules = builtins.concatMap simple-modules-builder categories;
in
{
  imports = simple-modules;
}
