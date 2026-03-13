{ pkgs, ... }: {
  systemd.packages = with pkgs; [ lact ];
  systemd.services.lactd.wantedBy = [ "multi-user.target" ];

  environment.systemPackages = with pkgs; [ lact ];

  #enable overclocking
  boot.modprobeConfig.enable = true;
  boot.extraModprobeConfig = ''
    options amdgpu ppfeaturemask=0xffffffff
  '';
}
