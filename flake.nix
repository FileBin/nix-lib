{
  description = "default vscode flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        nix-lib = (import ./lib) { inherit pkgs; };
      in
      {
        devShells.default = (import ./shell.nix) {
          inherit pkgs;
          inherit nix-lib;
        };
      }
    );
}
