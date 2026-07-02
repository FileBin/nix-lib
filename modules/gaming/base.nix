{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  boot.kernelModules = [ "ntsync" ];
  boot.kernelParams = [ "split_lock_detect=off" ];

  programs.steam = {
    enable = true;
    extraPackages = with pkgs; [
      gamescope
      gamemode
      mangohud
      nspr
    ];
  };

  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    gamescope
    wineWowPackages.stable
    lutris
    protonup-qt
    mangohud
    unstable.vesktop
    bottles
  ];
}
