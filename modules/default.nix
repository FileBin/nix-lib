{ pkgs, ... }:
let
  list-modules = (import ../lib/list-modules.nix) { inherit pkgs; };
  make-simple-module = (import ../lib/make-simple-module.nix) { inherit pkgs; };

  simple-modules = map (x: make-simple-module x) (list-modules ./simple);
  complex-modules = map (path: import path) (list-modules ./complex);
in
{
  imports = simple-modules ++ complex-modules;
}
