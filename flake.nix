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
  };

  outputs =
    { nixpkgs, flake-utils, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        llama-vulkan-test = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs system;
          };
          modules = [
            ./integration-tests/llama-vulkan-unload
          ];
        };
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        nix-lib = (import ./lib) { inherit pkgs; };
        merge-modules = (import ./lib/merge-modules.nix) { inherit pkgs; };
        list-modules = (import ./lib/list-modules.nix) { inherit pkgs; };
        nix-shared = (import "${inputs.nix-shared}");
      in
      {
        devShells.default = (import ./shell.nix) {
          inherit pkgs;
          inherit nix-lib;
          inherit nix-shared;
        };

        checks.llama-vulkan-unload = (import ./desktop-modules/llama-vulkan-unload/check.nix) {
          inherit pkgs nixpkgs system;
        };

      } // (merge-modules (list-modules ./desktop-modules))
    );
}
