{ pkgs, ... }:
rec {
  mkUixShell = pkgs.callPackage (import ./mkUixShell.nix) { };
  mkUixVscodeShell = pkgs.callPackage (import ./mkUixVscodeShell.nix { inherit mkUixShell; }) { };
}
