{ pkgs, ... }:
configPath:
let
  module-name = pkgs.lib.removeSuffix ".nix" (baseNameOf configPath);
in
{ pkgs, config, lib, inputs, system, ...}@args:
let config-src = import configPath;
  unwrapped-config = if builtins.isFunction config-src then config-src args else config-src;
  imports = unwrapped-config.imports or [];
  clean-config = removeAttrs unwrapped-config [ "imports" ];
in {
  inherit imports;

  options = {
    simple.${module-name} = lib.mkEnableOption "Enables ${module-name}";
  };

  config = lib.mkIf config.simple.${module-name} clean-config;
}


