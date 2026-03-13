{ config, pkgs, ... }: {
  boot.kernelModules = [ "legion-laptop" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.lenovo-legion-module ];

  environment.systemPackages = [
    pkgs.lenovo-legion
  ];
}
