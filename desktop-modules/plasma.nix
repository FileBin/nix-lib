{ pkgs, ... }: {
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  programs.kdeconnect.enable = true;

  environment.systemPackages = with pkgs.kdePackages; [
    xdg-desktop-portal-kde
    qtsvg
    dolphin
    dolphin-plugins
    kde-gtk-config
    kcolorchooser

    # KDE
    kate
    kcalc # Calculator
    kcharselect # Tool to select and copy special characters from all installed fonts
    kclock # Clock app
    kcolorchooser # A small utility to select a color
    ksystemlog # KDE SystemLog Application
    sddm-kcm # Configuration module for SDDM
    pkgs.kdiff3 # Compares and merges 2 or 3 files or directories
    isoimagewriter # Optional: Program to write hybrid ISO files onto USB disks
  ];
}
