{ pkgs, ... }:

let
  dirContents = builtins.readDir ./.;

  processItem = path: type:
    let
      isNixFile = type == "regular" && pkgs.lib.hasSuffix ".nix" path && path != "default.nix";
      isDirWithDefault = type == "directory" && builtins.pathExists (./. + "/${path}/default.nix");
    in
    if isNixFile then {
      name = pkgs.lib.removeSuffix ".nix" path;
      value = import (./. + "/${path}");
    }
    else if isDirWithDefault then {
      name = path;
      value = import (./. + "/${path}");
    }
    else null;

  pairs = pkgs.lib.mapAttrsToList processItem dirContents;
  validPairs = builtins.filter (x: x != null) pairs;

in
  builtins.listToAttrs validPairs