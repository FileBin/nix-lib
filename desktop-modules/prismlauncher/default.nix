{ pkgs, ... }:
let
  prismlauncher-cracked = pkgs.prismlauncher-unwrapped.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [
      ./prismlauncher-remove-drm.patch
    ];
  });

  prismlauncher-custom = pkgs.prismlauncher.override {
    prismlauncher-unwrapped = prismlauncher-cracked;
    jdks = [ pkgs.jdk25 ];
  };
in
{
  environment.systemPackages = [ prismlauncher-custom ];
}
