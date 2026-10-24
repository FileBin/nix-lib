{ pkgs, ... }:
dir:
let
  lib = pkgs.lib;

  modules = lib.collect lib.isString (
    lib.mapAttrsRecursive (path: type: lib.concatStringsSep "/" path) (builtins.readDir dir)
  );
in
map (file: dir + "/${file}") (
  # Только .nix-файлы: соседние ассеты (шаблоны, скрипты) не должны импортироваться.
  lib.filter (file: lib.hasSuffix ".nix" file && file != "default.nix") modules
)
