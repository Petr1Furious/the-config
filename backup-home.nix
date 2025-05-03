{
  config,
  lib,
  pkgs,
  ...
}:

{
  backup.backups.home = {
    paths = [
      "/home/petrtsopa"
      "/root"
    ];
    extraBackupArgs = [
      "--exclude=/home/petrtsopa/.cache"
      "--exclude=/root/.cache"
    ];
  };
}
