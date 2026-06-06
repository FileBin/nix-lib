{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    waypipe
  ];
}
