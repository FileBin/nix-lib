{ pkgs, nixpkgs, system }:

let
  # Script to verify all required Vulkan layer entry points are exported from the .so
  check-symbols = pkgs.writeShellScriptBin "check-llama-layer-symbols" ''
    LIB="/run/current-system/sw/lib/libVkLayer_llama_unload.so"
    REQUIRED_SYMBOLS=(
      vkNegotiateLoaderLayerInterfaceVersion
      vkGetInstanceProcAddr
      vkGetDeviceProcAddr
      vk_layerGetPhysicalDeviceProcAddr
    )
    MISSING=0
    for sym in "''${REQUIRED_SYMBOLS[@]}"; do
      if ! nm -D "$LIB" | grep -q "$sym"; then
        echo "FAIL: missing symbol: $sym"
        MISSING=1
      fi
    done
    exit "$MISSING"
  '';

  # Script to verify the layer manifest JSON file exists and is valid.
  check-layer-manifest = pkgs.writeShellScriptBin "check-layer-manifest" ''
    set -e
    MANIFEST="/run/current-system/sw/share/vulkan/implicit_layer.d/VkLayer_llama_unload.json"
    if [ ! -f "$MANIFEST" ]; then
      echo "FAIL: layer manifest not found at $MANIFEST"
      exit 1
    fi
    # Verify the manifest contains the expected layer name
    if ! grep -q '"VK_LAYER_llama_unload"' "$MANIFEST"; then
      echo "FAIL: manifest does not contain VK_LAYER_llama_unload"
      exit 1
    fi
    echo "OK: layer manifest is valid"
  '';

in
pkgs.testers.runNixOSTest {
  name = "llama-vulkan-unload-check";

  # Use containers (systemd-nspawn) for fast, lightweight testing.
  # Requires nix daemon settings:
  #   auto-allocate-uids = true;
  #   experimental-features = [ "auto-allocate-uids" "cgroups" ];
  #   extra-system-features = [ "uid-range" ];
  containers.machine = {
    imports = [
      ./default.nix
      ../llama-cpp-single-gpu.nix
    ];

    services.llama-vulkan-unload.enable = true;

    boot.isContainer = true;
    system.stateVersion = "26.05";

    # Disable getty for headless container
    systemd.services."getty@tty1".enable = false;
    systemd.services."serial-getty@ttyS0".enable = false;

    # Tools needed for testing
    environment.systemPackages = [
      pkgs.binutils      # nm
      check-symbols
      check-layer-manifest
    ];
  };

  testScript = ''
    machine.wait_for_unit("default.target")

    # 1. Verify the layer .so file exists
    machine.succeed("test -e /run/current-system/sw/lib/libVkLayer_llama_unload.so")

    # 2. Verify required Vulkan layer symbols are exported
    machine.succeed("check-llama-layer-symbols")

    # 3. Verify the layer manifest is valid and visible
    machine.succeed("check-layer-manifest")
  '';
}
