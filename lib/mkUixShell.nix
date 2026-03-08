{ pkgs, ... }:
{
  uixShellGuid,
  uixHook ? "",
  ...
}@args:
let
  uixrc = pkgs.writeScript "uixrc" ''
    export UIX_ID="${uixShellGuid}"
    export UIX_TMPDIR="/tmp/uix-shell/$UIX_ID"
    export UIX_DATADIR="$HOME/.local/share/uix/devshells/$UIX_ID"

    mkdir -p "$UIX_TMPDIR"
    mkdir -p "$UIX_DATADIR"
  '';

  shellHook = ''
    source ${uixrc}
    ${uixHook}
  '';

  cleanArgs = removeAttrs args [
    "shellHook"
  ];
in
pkgs.mkShell (cleanArgs // { inherit shellHook; })
