{ config, ... }: {
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];

  environment.systemPackages = [ config.boot.kernelPackages.v4l2loopback ];
}
