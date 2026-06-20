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

  llamaPkg = builtins.head (pkgs.lib.filter (p: p.name == "llama-vulkan-unload") systemConfig.config.environment.systemPackages);
in
pkgs.runCommand "llama-vulkan-unload-test"
  {
    nativeBuildInputs = [ pkgs.jq pkgs.binutils ];
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

    echo "=== All checks passed ==="
    touch $out
  ''
