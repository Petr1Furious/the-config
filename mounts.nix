{
  config,
  lib,
  pkgs,
  ...
}:
{
  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_1TB_S6Z1NF0W700873F";
    fsType = "ext4";
  };
}
