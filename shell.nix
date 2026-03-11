{ pkgs, nix-lib, nix-shared, ... }:

with pkgs;
nix-lib.mkUixVscodeShell {
  uixShellGuid = "56c1d145-77bc-47ef-8eb3-ac0126f158f1";

  vscodeOptions.userSettings = nix-shared.vscode-settings;

  vscodeExtensions =
    with vscode-extensions;
    [
      tal7aouy.icons
      jnoortheen.nix-ide
      wmaurer.change-case
      gruntfuggly.todo-tree
      redhat.vscode-xml
      ms-python.python
    ]
    ++ vscode-utils.extensionsFromVscodeMarketplace [
      {
        name = "linux-desktop-file";
        publisher = "nico-castell";
        version = "0.0.21";
        hash = "sha256-4qy+2Tg9g0/9D+MNvLSgWUE8sc5itsC/pJ9hcfxyVzQ=";
      }
    ];

  packages = [
    nixd
    python3
  ];
}
