{
  config,
  lib,
  pkgs,
  ...
}:
{
  fileSystems."/backup" = {
    device = "/dev/disk/by-uuid/a22f022b-6ae0-47cf-84e5-a8f231b6b458";
    fsType = "ext4";
  };
}
