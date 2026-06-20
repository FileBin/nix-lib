# Declarative NixOS container configuration for llama-vulkan-unload integration testing.
#
# Spawn with:
#   nixos-container create llama-vulkan-test \
#     --flake github:FileBin/nix-lib#llama-vulkan-test
#   nixos-container start llama-vulkan-test
#   nixos-container enter llama-vulkan-test
#
# Then run the integration test manually.

{ pkgs, ... }: {
  imports = [
    ../../desktop-modules/llama-cpp-single-gpu.nix
    ../../desktop-modules/llama-vulkan-unload/default.nix
  ];

  services.llama-vulkan-unload.enable = true;

  boot.isContainer = true;
  system.stateVersion = "26.05";

  # Headless — no getty
  systemd.services."getty@tty1".enable = false;
  systemd.services."serial-getty@ttyS0".enable = false;

  # Tools needed for testing
  environment.systemPackages = [
    pkgs.vulkan-tools  # vulkaninfo
    pkgs.curl
    pkgs.jq
  ];
}
