{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    clinfo
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    rocmPackages.rocm-core
  ];
  useRocm = true;
}
