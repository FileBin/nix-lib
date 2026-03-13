{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  boot.kernelModules = [ "ntsync" ];

  programs.steam = {
    enable = true;
    extraPackages = with pkgs; [
      gamescope
      gamemode
      mangohud
    ];
  };

  programs.gamemode.enable = true;

  environment.systemPackages = with pkgs; [
    steam-run
    gamescope
    wineWowPackages.stable
    lutris
    protonup-qt
    mangohud
    unstable.vesktop
  ];
}
