{ pkgs, nixpkgs, system }:

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
  };

  testScript = ''
    machine.wait_for_unit("default.target")
    machine.succeed("test -e /run/current-system/sw/lib/libVkLayer_llama_unload.so")
  '';
}
