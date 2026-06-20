# NixOS Container Testing for Desktop Modules

## Table of Contents
- [Why nixos-container](#why-nixos-container)
- [Basic container test pattern](#basic-container-test-pattern)
- [Adding the test to flake.nix](#adding-the-test-to-flake-nix)
- [Common test assertions](#common-test-assertions)
- [Container-specific options](#container-specific-options)

## Why nixos-container

nixos-container runs a full NixOS system in a lightweight container (no VM overhead). It is faster than `testLib.makeTest` for testing modules that don't require hardware emulation or networking isolation.

Key advantage: the container shares the host kernel, so tests build and run quickly.

## Basic container test pattern

Create a test derivation that:

1. Builds a minimal NixOS config importing your module
2. Deploys it as a container
3. Enters the container and runs assertions

```nix
# In your flake checks:
my-module-test = let
  testConfig = { pkgs, ... }: {
    imports = [
      # Path to your module
      ./desktop-modules/<name>.nix
    ];

    # Enable the module
    services.<module-name>.enable = true;

    # Minimal container config
    boot.isContainer = true;
    system.stateVersion = "26.05";

    # Disable interactive services that block container startup
    systemd.services."getty@tty1".enable = false;
    systemd.services."serial-getty@ttyS0".enable = false;
  };

  system = (import <nixpkgs/nixos>) {
    inherit (pkgs) system;
    modules = [ testConfig ];
  };
in
pkgs.runCommand "my-module-test" { } ''
  # Use nixos-container to create and test
  nixos-container create my-test --system "${system.config.system.build.toplevel}"
  nixos-container start my-test

  # Wait for container to be ready
  sleep 5

  # Run assertions inside the container
  nixos-container run my-test -- \
    bash -c '
      set -e
      # Example: check a service is running
      systemctl is-active my-service

      # Example: check a command exists
      which my-command

      # Example: check a config file
      grep -q "expected" /etc/my-config
    '

  # Cleanup
  nixos-container stop my-test
  nixos-container remove my-test

  touch $out
'';
```

## Adding the test to flake.nix

In the project `flake.nix`, add the check under `checks.<system>`:

```nix
outputs = { self, nixpkgs, flake-utils, ... }:
flake-utils.lib.eachDefaultSystem (system:
  let
    pkgs = import nixpkgs { inherit system; };
    nixosSystem = nixpkgs.lib.nixosSystem;
  in
  {
    checks."<name>-test" = let
      testConfig = { pkgs, ... }: {
        imports = [ ./desktop-modules/<name>.nix ];
        services.<module-name>.enable = true;
        boot.isContainer = true;
        system.stateVersion = "26.05";
        systemd.services."getty@tty1".enable = false;
      };
      system = nixosSystem { inherit pkgs; modules = [ testConfig ]; };
    in
    pkgs.runCommand "<name>-test" { } ''
      nixos-container create my-test --system "${system.config.system.build.toplevel}"
      nixos-container start my-test
      sleep 5
      nixos-container run my-test -- bash -c 'set -e; systemctl is-active my-service'
      nixos-container stop my-test
      nixos-container remove my-test
      touch $out
    '';
  }
);
```

Run with:

```bash
nix flake check
```

## Common test assertions

| What to test | Command |
|---|---|
| Service is active | `systemctl is-active <service>` |
| Package installed | `which <command>` or `<command> --version` |
| File exists | `test -f /path/to/file` |
| File contains text | `grep -q "pattern" /path/to/file` |
| Directory exists | `test -d /path/to/dir` |
| User exists | `id <username>` |
| Group exists | `getent group <groupname>` |
| Port is listening | `ss -tln \| grep :<port>` |

## Container-specific options

These options often need to be set in the test config:

| Option | Purpose |
|---|---|
| `boot.isContainer = true` | Tells NixOS this is a container (disables certain boot services) |
| `systemd.services."getty@tty1".enable = false` | Prevents login prompt from blocking |
| `systemd.services."serial-getty@ttyS0".enable = false` | Prevents serial getty from blocking |
| `system.stateVersion` | Required to avoid warnings |
| `boot.kernelPackages` | May need to match host kernel in containers |

## When nixos-container is not enough

Use `testLib.makeTest` (VM-based testing) when:
- The module requires specific hardware (GPU, USB devices)
- The module depends on kernel modules not available on the host
- Network isolation is required between test subjects

Read more: [NixOS Testing Framework](https://nixos.wiki/wiki/NixOS_tests)
