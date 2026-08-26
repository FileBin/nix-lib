{
  boot.loader.grub.enable = true;
  boot.loader.grub.useOSProber = true;
  # Use provided UUIDs instead of blkid probing (required for btrfs subvolumes)
  boot.loader.grub.fsIdentifier = "provided";
}