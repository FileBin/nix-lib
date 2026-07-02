{
  pkgs,
  config,
  lib,
  ...
}:

let
  cfg = config.services.llama-vulkan-unload;
  llama-apiBase = "http://localhost:${toString cfg.port}";

  # ------------------------------------------------------------------
  # Bundled package — layer library + manifest (MangoHUD pattern)
  # ------------------------------------------------------------------
  llama-vulkan-unload-pkg = pkgs.callPackage ./package.nix {
    inherit llama-apiBase;
  };

  # ------------------------------------------------------------------
  # Wrapper script — sets FREE_LLAMA_VRAM=1 for the command
  # ------------------------------------------------------------------
  llama-game = pkgs.writeShellApplication {
    name = "llama-game";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      export FREE_LLAMA_VRAM=1
      exec "$@"
    '';
  };
in
{
  options = {
    services.llama-vulkan-unload = {
      enable = lib.mkEnableOption "llama-vulkan-unload Vulkan layer (unloads llama.cpp models when a Vulkan app starts)";

      port = lib.mkOption {
        type = lib.types.port;
        default = config.services.llama-cpp.port;
        description = "Port of the llama.cpp server (must match services.llama-cpp.port)";
      };

      package = lib.mkOption {
        type = lib.types.package;
        description = "The llama-game wrapper package";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.llama-vulkan-unload.package = lib.mkDefault llama-game;

    /*
      The bundled package installs both the layer library and manifest
      to $out/lib/ and $out/share/vulkan/implicit_layer.d/ respectively.
      The manifest uses $out/lib/ as library_path (MangoHUD pattern).
    */
    environment.systemPackages = [
      llama-vulkan-unload-pkg
      llama-game
    ];
  };
}
