{ mkUixShell }:
{ pkgs, lib, ... }:
{
  uixHook ? "start-vscode",
  uixShellGuid,
  packages ? [ ],
  vscodeExtensions ? [ ],
  vscodeOptions ? { },
  ...
}@args:
let
  userSettings = vscodeOptions.userSettings or { };

  packagesWrap = packages ++ [
    start-vscode
    pkgs.vscode
    pkgs.bashInteractive
  ];

  extensionJsonFile = pkgs.writeTextFile {
    name = "vscode-extensions-json";
    destination = "/share/vscode/extensions/extensions.json";
    text = pkgs.vscode-utils.toExtensionJson vscodeExtensions;
  };

  combinedExtensionsDrv = pkgs.buildEnv {
    name = "vscode-extensions";
    paths = vscodeExtensions ++ [ extensionJsonFile ];
  };

  start-vscode =
    let
      # TODO move it to nix-lib function
      overwrite-link =
        { src, dest }:
        let
          src-dir = builtins.dirOf src;
        in
        ''
          [ ! -e "${src-dir}" ] && mkdir -p "${src-dir}"
          [ ! -e "${dest}" ] && mkdir -p "${dest}"
          rm -rf "${src}"
          ln -s "${dest}" "${src}"
        '';
      # directories that i dont want to keep on disk, and moving it to /tmp
      cache-directories = [
        "Cache"
        "CachedConfigurations"
        "CachedData"
        "CachedProfilesData"
        "Code Cache"
        "DawnGraphiteCache"
        "DawnWebGPUCache"
        "GPUCache"
      ];

      userSettingsJSON = pkgs.writeText "${uixShellGuid}-userSettings.json" (
        builtins.toJSON userSettings
      );
    in
    pkgs.writeShellScriptBin "start-vscode" ''
      USER_DATA_DIR="$UIX_DATADIR/vscode/userdata"
      USER_DATA_CACHE_DIR="$UIX_TMPDIR/vscode/userdata_cache"

      mkdir -p $USER_DATA_DIR

      # symlink cache directories to not keep it on disk
      ${builtins.concatStringsSep "\n" (
        lib.lists.forEach cache-directories (
          dir:
          overwrite-link {
            src = "$USER_DATA_DIR/${dir}";
            dest = "$USER_DATA_CACHE_DIR/${dir}";
          }
        )
      )}

      # symlink userSettings.json
      ${overwrite-link {
        src = "$USER_DATA_DIR/User/settings.json";
        dest = userSettingsJSON;
      }}

      TMPDIR="$UIX_TMPDIR" code --extensions-dir "${combinedExtensionsDrv}/share/vscode/extensions" --user-data-dir="$USER_DATA_DIR" .
    '';

  cleanArgs = removeAttrs args [
    "uixHook"
    "packages"
    "vscodeOptions"
  ];
in
mkUixShell (cleanArgs // { packages = packagesWrap; inherit uixHook; })
