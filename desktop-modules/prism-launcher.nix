{ pkgs, ... }:
let
  prismlauncher-custom = pkgs.prismlauncher.override {
    jdks = [ pkgs.jdk25 ];
  };
in
{
  environment.systemPackages = [ prismlauncher-custom ];
}
