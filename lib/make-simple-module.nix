{ pkgs, ... }:
{category, path}:
let
  module-name = pkgs.lib.removeSuffix ".nix" (baseNameOf path);
in
{ pkgs, config, lib, ... }@args:
let config-src = import path;
  moduleConfig = config.${category}.${module-name};

  additionalArgs = {
    inherit moduleConfig;
  };

  enableOption = {
    enable = lib.mkEnableOption "Enables ${module-name}";
  };

  isSimple = !(builtins.hasAttr "customOptions" unwrapped-config);

  customArgs = args // additionalArgs;
  customOptions = if isSimple then enableOption.enable else (enableOption // unwrapped-config.customOptions);

  unwrapped-config = if builtins.isFunction config-src then config-src customArgs else config-src;
  imports = unwrapped-config.imports or [];
  clean-config = removeAttrs unwrapped-config [ "imports" "customOptions" ];

  enabled = if isSimple then moduleConfig else moduleConfig.enable;
in {
  inherit imports;

  options.${category}.${module-name} = customOptions;

  config = lib.mkIf enabled clean-config;
}


