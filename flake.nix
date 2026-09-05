{
  description = "default vscode flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    nix-shared = {
      url = "http://gitea.home/filebin/nix-shared/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    agenix = {
      url = "github:ryantm/agenix";

      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        nix-lib-gen = lib: (import ./lib) { inherit pkgs lib system; };
        nix-lib = nix-lib-gen pkgs.lib;
        nix-shared = (import "${inputs.nix-shared}");
      in
      {
        libExtension = selfLib: nix-lib-gen;

        lib = nixpkgs.lib.extend self.libExtension;

        formatter = pkgs.nixfmt;

        devShells.default = (import ./shell.nix) {
          inherit pkgs;
          inherit nix-lib;
          inherit nix-shared;
        };

        checks.llama-vulkan-unload = (import ./desktop-modules/llama-vulkan-unload/check.nix) {
          inherit pkgs;
        };

        nixosModules.default = (import ./modules) { inherit pkgs inputs system; };
      }
    );
}
