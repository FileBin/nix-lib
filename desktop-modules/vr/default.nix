{ pkgs, ... }:
{
  # boot.kernelPatches = [
  #   {
  #     name = "amdgpu-ignore-ctx-privileges";
  #     patch = pkgs.fetchpatch {
  #       name = "cap_sys_nice_begone.patch";
  #       url = "https://github.com/Frogging-Family/community-patches/raw/master/linux61-tkg/cap_sys_nice_begone.mypatch";
  #       hash = "sha256-Y3a0+x2xvHsfLax/uwycdJf3xLxvVfkfDVqjkxNaYEo=";
  #     };
  #   }
  # ];

  # SteamVR Fix
  # programs.steam =
  #   let
  #     patchedBwrap = pkgs.bubblewrap.overrideAttrs (o: {
  #       patches = (o.patches or [ ]) ++ [
  #         ./bwrap.patch
  #       ];
  #     });
  #   in
  #   {
  #     package = pkgs.steam.override {
  #       buildFHSEnv = (
  #         args:
  #         (
  #           (pkgs.buildFHSEnv.override {
  #             bubblewrap = patchedBwrap;
  #           })
  #           (
  #             args
  #             // {
  #               extraBwrapArgs = (args.extraBwrapArgs or [ ]) ++ [ "--cap-add ALL" ];
  #             }
  #           )
  #         )
  #       );
  #     };
  #   };

  services.monado = {
    enable = true;
    defaultRuntime = true; # Register as default OpenXR runtime
    # package = pkgs.monado.overrideAttrs (old: {
    #   cmakeFlags = old.cmakeFlags ++ [ "-DBUILD_WITH_OPENCV=OFF" ];
    # });
  };

  environment.systemPackages = [
    pkgs.onnxruntime
  ];

  environment.etc."xdg/openxr/1/active_runtime.json".source = "${pkgs.monado}/share/openxr/1/openxr_monado.json";
  environment.variables = { VIT_SYSTEM_LIBRARY_PATH="${pkgs.basalt-monado}/lib/libbasalt.so"; };

  imports = [ ./udev-rules.nix ];
}
