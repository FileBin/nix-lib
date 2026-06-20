{
  pkgs,
  nixpkgs,
  system,
}:

let
  testConfig = { pkgs, ... }: {
    imports = [
      ./default.nix
      ../llama-cpp-single-gpu.nix
    ];

    services.llama-vulkan-unload.enable = true;

    boot.isContainer = true;
    system.stateVersion = "26.05";
    systemd.services."getty@tty1".enable = false;
    systemd.services."serial-getty@ttyS0".enable = false;
  };

  systemConfig = nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [ testConfig ];
  };

  llamaPkg = builtins.head (
    pkgs.lib.filter (p: p.name == "llama-vulkan-unload") systemConfig.config.environment.systemPackages
  );
in
pkgs.runCommand "llama-vulkan-unload-test"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.binutils
      pkgs.vulkan-tools # vulkaninfo
      pkgs.mesa.drivers
    ];
  }
  ''
    TOPOLEVEL="${systemConfig.config.system.build.toplevel}"
    LLAMA_GAME="${systemConfig.config.services.llama-vulkan-unload.package}"
    LLAMA_PKG="${llamaPkg}"

    echo "=== Checking llama-vulkan-unload package ==="

    # 1. Verify the layer .so exists
    test -f "$LLAMA_PKG/lib/libVkLayer_llama_unload.so"
    echo "  [PASS] libVkLayer_llama_unload.so exists"

    # 2. Verify the Vulkan layer manifest exists and is valid JSON
    MANIFEST="$LLAMA_PKG/share/vulkan/implicit_layer.d/VkLayer_llama_unload.json"
    test -f "$MANIFEST"
    echo "  [PASS] Manifest exists"

    # 3. Verify the manifest contains the correct layer name
    grep -q "VK_LAYER_llama_unload" "$MANIFEST"
    echo "  [PASS] Layer name correct"

    # 4. Verify the layer .so library path referenced in manifest exists
    LIB_PATH=$(cat "$MANIFEST" | jq -r '.layer.library_path')
    test -f "$LIB_PATH"
    echo "  [PASS] Library path in manifest exists: $LIB_PATH"

    # 5. Verify required Vulkan layer symbols are exported
    for sym in vkNegotiateLoaderLayerInterfaceVersion vkGetInstanceProcAddr vkGetDeviceProcAddr vk_layerGetPhysicalDeviceProcAddr; do
      nm -D "$LLAMA_PKG/lib/libVkLayer_llama_unload.so" | grep -q "$sym"
    done
    echo "  [PASS] Required Vulkan layer symbols exported"

    # 6. Verify curl symbols are linked (libcurl integration)
    nm -D "$LLAMA_PKG/lib/libVkLayer_llama_unload.so" | grep -q "curl_easy_init"
    echo "  [PASS] libcurl symbols linked"

    # 7. Verify llama-game wrapper derivation exists
    test -f "$LLAMA_GAME/bin/llama-game"
    echo "  [PASS] llama-game wrapper exists"

    # 8. Verify llama-cpp service is configured in toplevel
    test -f "$TOPOLEVEL/etc/systemd/system/llama-cpp.service"
    echo "  [PASS] llama-cpp.service exists in toplevel"

    # 9. Verify vulkaninfo runs without hanging or segfaulting
    #    Run with a 15-second timeout; capture both stdout and stderr.
    #    A successful run exits 0 and produces output; timeout>0 means hang,
    #    signal 11 means segfault, any other non-zero exit is a failure.
    VULKAN_INFO_OUTPUT=$(timeout 15s vulkaninfo --summary 2>&1) || {
      VULKAN_INFO_EXIT=$?
      if [ "$VULKAN_INFO_EXIT" -eq 124 ]; then
        echo "  [FAIL] vulkaninfo timed out after 15s (hang detected)"
      elif [ "$VULKAN_INFO_EXIT" -eq 139 ]; then
        echo "  [FAIL] vulkaninfo segfaulted (exit code 139 = 128+11)"
      else
        echo "  [FAIL] vulkaninfo exited with code $VULKAN_INFO_EXIT"
      fi
      echo "  Output: $VULKAN_INFO_OUTPUT" >&2
      exit 1
    }
    echo "  [PASS] vulkaninfo runs successfully (no hang, no segfault)"

    # 10. Verify vulkaninfo runs with the llama-unload layer loaded
    #      Set FREE_LLAMA_VRAM=1 to enable the layer and VK_LAYER_PATH so
    #      the loader finds the manifest in the build sandbox.
    VULKAN_LAYER_OUTPUT=$(
      FREE_LLAMA_VRAM=1 \
      VK_LAYER_PATH="$LLAMA_PKG/share/vulkan/" \
      timeout 15s vulkaninfo --summary >/dev/null 2>&1
    ) || {
      VULKAN_LAYER_EXIT=$?
      if [ "$VULKAN_LAYER_EXIT" -eq 124 ]; then
        echo "  [FAIL] vulkaninfo with llama-unload layer timed out after 15s (hang detected)"
      elif [ "$VULKAN_LAYER_EXIT" -eq 139 ]; then
        echo "  [FAIL] vulkaninfo with llama-unload layer segfaulted (exit code 139 = 128+11)"
      else
        echo "  [FAIL] vulkaninfo with llama-unload layer exited with code $VULKAN_LAYER_EXIT"
      fi
      echo "  Output: $VULKAN_LAYER_OUTPUT" >&2
      exit 1
    }
    echo "  [PASS] vulkaninfo runs with llama-unload layer loaded (no hang, no segfault)"

    echo "=== All checks passed ==="
    touch $out
  ''
