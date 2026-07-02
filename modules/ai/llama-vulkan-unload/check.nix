{
  pkgs, ...
}:

let
  # Script to verify all required Vulkan layer entry points are exported from the .so
  check-symbols = pkgs.writeShellScriptBin "check-llama-layer-symbols" ''
    LIB="/run/current-system/sw/lib/libVkLayer_llama_unload.so"
    REQUIRED_SYMBOLS=(
      vkNegotiateLoaderLayerInterfaceVersion
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

  # Script to verify vulkaninfo runs and sees the llama-unload layer
  # when the activation env var (FREE_LLAMA_VRAM) is NOT set.
  check-vulkaninfo-without-activation = pkgs.writeShellScriptBin "check-vulkaninfo-without-activation" ''
    set -e
    # Ensure FREE_LLAMA_VRAM is not set
    unset FREE_LLAMA_VRAM
    # Run vulkaninfo and check that the llama-unload layer appears
    OUTPUT=$(vulkaninfo --summary 2>&1) || {
      echo "FAIL: vulkaninfo itself failed"
      echo "$OUTPUT"
      exit 1
    }
    if ! echo "$OUTPUT" | grep -q "VK_LAYER_llama_unload"; then
      echo "FAIL: llama-unload layer not visible in vulkaninfo output"
      echo "--- vulkaninfo output ---"
      echo "$OUTPUT"
      echo "--- end ---"
      exit 1
    fi
    echo "OK: llama-unload layer visible in vulkaninfo (without activation)"
  '';

  # Script to verify vulkaninfo runs successfully (no segfault/hang)
  # with the llama layer activated via FREE_LLAMA_VRAM=1.
  # NOTE: This test is expected to FAIL until the layer is working
  # properly, because the application will not work with the active
  # llama layer in its current state.
  check-vulkaninfo-with-activation = pkgs.writeShellScriptBin "check-vulkaninfo-with-activation" ''
    set -e
    # Activate the llama unload layer
    export FREE_LLAMA_VRAM=1
    # Enable Vulkan loader debug output
    export VK_LOADER_DEBUG=all
    # Clear previous debug log
    rm -f /tmp/llama_layer_debug.log
    # Run vulkaninfo with a timeout to detect hangs (30s)
    # If this succeeds, the layer does not crash/hang the application
    OUTPUT=$(timeout 30 vulkaninfo --summary 2>&1) || {
      EXIT_CODE=$?
      echo "FAIL: vulkaninfo crashed or hung with FREE_LLAMA_VRAM=1 (exit code=$EXIT_CODE)"
      echo "--- vulkaninfo output (last 100 lines) ---"
      echo "$OUTPUT" | tail -100
      echo "--- end vulkaninfo output ---"
      # Print the layer's own debug log if available
      if [ -f /tmp/llama_layer_debug.log ]; then
        echo "--- layer debug log (last 100 lines) ---"
        tail -100 /tmp/llama_layer_debug.log
        echo "--- end layer debug log ---"
      fi
      exit 1
    }
    echo "OK: vulkaninfo completed successfully with FREE_LLAMA_VRAM=1"
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

    # Enable software Vulkan via Mesa llvmpipe for headless testing
    hardware.graphics.enable = true;

    # Disable getty for headless container
    systemd.services."getty@tty1".enable = false;
    systemd.services."serial-getty@ttyS0".enable = false;

    # Tools needed for testing
    environment.systemPackages = [
      pkgs.binutils # nm
      pkgs.vulkan-tools # vulkaninfo
      check-symbols
      check-layer-manifest
      check-vulkaninfo-without-activation
      check-vulkaninfo-with-activation
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

    # 4. Verify vulkaninfo runs and sees llama-unload without activated layer
    machine.succeed("check-vulkaninfo-without-activation")

    # 5. Verify vulkaninfo runs successfully with active llama layer
    machine.succeed("check-vulkaninfo-with-activation")
  '';
}
