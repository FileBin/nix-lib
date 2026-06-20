---
name: create-desktop-module
description: Create a new NixOS desktop module in desktop-modules/ with nixos-container testing. Use when adding a new service, hardware config, or system feature to the nix-lib desktop-modules collection. Covers module scaffolding, option definition, and container-based integration tests.
---

# Create Desktop Module

## When to use
- Adding a new NixOS desktop module (service, hardware config, system feature) to `desktop-modules/`
- The module needs to be testable in a nixos-container

## When NOT to use
- Editing an existing module — edit the `.nix` file directly
- Creating server modules — they live in `server-modules/` with different patterns
- Adding a library function — use `lib/` instead

## Project structure

The project auto-discovers modules from `desktop-modules/`:

- `desktop-modules/default.nix` — reads all `.nix` files and subdirectories with `default.nix`
- `lib/list-modules.nix` — collects module paths
- `lib/merge-modules.nix` — folds them into `nixosModules`
- `flake.nix` — exposes modules via `merge-modules (list-modules ./desktop-modules)`

A module can be:
1. A flat file: `desktop-modules/mymodule.nix`
2. A directory: `desktop-modules/mymodule/default.nix` (use when the module has patches, udev rules, or multiple files)

## Workflow

### 1. Gather requirements

Ask the user:
- **Module name** (kebab-case, matches service or feature)
- **What it configures** (services, packages, options, hardware)
- **Test expectations** — what should pass in the container?

If requirements are unclear, **ask the user to provide a concrete test case** before writing the module.

### 2. Scaffolding

Create the module file at `desktop-modules/<name>.nix` (or `desktop-modules/<name>/default.nix` for multi-file modules).

For a basic module, use the template in [`assets/module-template.nix`](assets/module-template.nix).

Key rules:
- Declare options with `mkOption` and `mkEnableOption` before using them
- Use `mkIf` to conditionally apply configuration
- Keep the module self-contained; reference other modules via `config.*`, not by importing them directly

### 3. Add options

Define options under `options.services.<name>` (or the appropriate namespace). Follow the pattern:

```nix
options = {
  services.my-module = {
    enable = mkEnableOption "My Module";
    setting = mkOption {
      type = types.str;
      default = "value";
      description = "What this setting does";
    };
  };
};
```

### 4. Write configuration

Use `config` block guarded by `mkIf`:

```nix
config = mkIf config.services.my-module.enable {
  # ...
};
```

### 5. Create nixos-container test

Add a container test in the flake `checks` output that validates the module in an isolated nixos-container.

Read the testing guide for the full pattern: [`references/testing.md`](references/testing.md).

The test should:
- Build a minimal NixOS config importing only the new module
- Run a container with that config
- Verify the expected state (services running, files present, commands succeed)

### 6. Verify

- Ensure the module name matches the file name (the auto-discovery in `desktop-modules/default.nix` derives the name from the filename)
- Run `nix flake check` to confirm the test passes
- Confirm the module appears in `nixosModules` output

## Troubleshooting

- **Module not appearing** — check `desktop-modules/default.nix` filters: the file must end in `.nix` and not be named `default.nix` at the top level
- **Container test hangs** — the container may need `boot.isContainer = true` or `systemd.services.getty@tty1.enable = false`
- **Option conflicts** — use `lib.mkOverride` to adjust priority when multiple modules set the same option
