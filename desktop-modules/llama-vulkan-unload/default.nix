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
  # C++ source — embedded via writeText to avoid unpack issues
  # ------------------------------------------------------------------
  layerSrc = pkgs.writeText "layer.cpp" (builtins.readFile ./layer.cpp);

  # ------------------------------------------------------------------
  # C++ Vulkan implicit layer — intercepts vkCreateInstance
  # ------------------------------------------------------------------
  layerLibrary = pkgs.stdenv.mkDerivation {
    name = "libVkLayer_llama_unload";

    dontUnpack = true;
    dontConfigure = true;

    nativeBuildInputs = [ pkgs.gcc ];
    buildInputs = [
      pkgs.vulkan-loader
      pkgs.vulkan-headers
    ];

    buildPhase = ''
      cp ${layerSrc} layer.cpp
      g++ -O2 -fPIC -shared -o libVkLayer_llama_unload.so \
        -DLLAMA_API_BASE="\"${llama-apiBase}\"" \
        layer.cpp \
        -lvulkan
    '';

    installPhase = ''
      mkdir -p $out/lib
      cp libVkLayer_llama_unload.so $out/lib/
    '';
  };

  # ------------------------------------------------------------------
  # Layer manifest JSON — registered with the Vulkan loader
  # ------------------------------------------------------------------
  layerManifest = pkgs.writeText "VkLayer_llama_unload.json" ''
    {
      "file_format_version": "1.0.0",
      "layer": {
        "name": "VK_LAYER_llama_unload",
        "type": "GLOBAL",
        "library_path": "${layerLibrary}/lib/libVkLayer_llama_unload.so",
        "api_version": "1.3.0",
        "implementation_version": "1",
        "description": "Unloads llama.cpp models to free up VRAM on Vulkan app start",
        "enable_environment": {
          "FREE_LLAMA_VRAM": "1"
        },
        "disable_environment": {
          "DISABLE_LLAMA_UNLOAD": "1"
        }
      }
    }
  '';

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
        default = 11433;
        description = "Port of the llama.cpp server (must match services.llama-cpp.port)";
      };

      package = lib.mkOption {
        type = lib.types.package;
        description = "The llama-game wrapper package";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.llama-vulkan-unload.package = llama-game;
    /*
      Install the Vulkan layer manifest to /etc/vulkan/implicit_layer.d/
      which the Vulkan loader searches on Linux. Using environment.etc
      ensures the file is in the NixOS toplevel.
    */
    environment.etc = {
      "vulkan/implicit_layer.d/VkLayer_llama_unload.json" = {
        source = layerManifest;
        mode = "0644";
      };
    };

    /*
      Ensure the layer library is accessible. The manifest references
      the absolute path, so no LD_LIBRARY_PATH is needed.
    */
    environment.systemPackages = [
      layerLibrary
      llama-game
    ];
  };
}
