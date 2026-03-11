{
  description = "default vscode flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    nix-shared = {
      url = "http://gitea.home/filebin/nix-shared/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    { nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        nix-lib = (import ./lib) { inherit pkgs; };
        nix-shared = (import "${inputs.nix-shared}");
      in
      {
        devShells.default = (import ./shell.nix) {
          inherit pkgs;
          inherit nix-lib;
          inherit nix-shared;
        };
      }
    );
}
