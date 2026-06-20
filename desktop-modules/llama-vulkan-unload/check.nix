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
    inherit (pkgs) system;
    modules = [ testConfig ];
  };
in
pkgs.runCommand "llama-vulkan-unload-test"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    TOPOLEVEL="${systemConfig.config.system.build.toplevel}"
    LLAMA_GAME="${systemConfig.config.services.llama-vulkan-unload.package}"

    # 1. Verify the Vulkan layer manifest exists in the toplevel
    test -f "$TOPOLEVEL/etc/vulkan/implicit_layer.d/VkLayer_llama_unload.json" \
      || test -f "$TOPOLEVEL/usr/share/vulkan/implicit_layer.d/VkLayer_llama_unload.json"

    # 2. Find the manifest file
    if [ -f "$TOPOLEVEL/etc/vulkan/implicit_layer.d/VkLayer_llama_unload.json" ]; then
      MANIFEST="$TOPOLEVEL/etc/vulkan/implicit_layer.d/VkLayer_llama_unload.json"
    else
      MANIFEST="$TOPOLEVEL/usr/share/vulkan/implicit_layer.d/VkLayer_llama_unload.json"
    fi

    # 3. Verify the manifest contains the correct layer name
    grep -q "VK_LAYER_llama_unload" "$MANIFEST"

    # 4. Verify the layer .so library path referenced in manifest exists
    LIB_PATH=$(cat "$MANIFEST" | jq -r '.layer.library_path')
    test -f "$LIB_PATH"

    # 5. Verify llama-cpp service is configured
    test -f "$TOPOLEVEL/etc/systemd/system/llama-cpp.service"

    # 6. Verify llama-game wrapper derivation exists
    test -f "$LLAMA_GAME/bin/llama-game"

    touch $out
  ''
