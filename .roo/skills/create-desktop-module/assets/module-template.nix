{ pkgs, config, lib, ... }:

let
  cfg = config.services.<module-name>;
in
{
  options = {
    services.<module-name> = {
      enable = lib.mkEnableOption "<Module Name>";

      # Add options here. Example:
      # setting = lib.mkOption {
      #   type = lib.types.str;
      #   default = "default-value";
      #   description = "What this setting does";
      # };
    };
  };

  config = lib.mkIf cfg.enable {
    # Add configuration here. Example:
    # environment.systemPackages = [ pkgs.some-package ];
    # systemd.services.my-service = { ... };
  };
}
