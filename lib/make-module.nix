{ pkgs, ... }:
configPath:
let
  name = pkgs.lib.removeSuffix ".nix" (builtins.baseNameOf configPath);
in
{
  "${name}" = (import configPath);
}
