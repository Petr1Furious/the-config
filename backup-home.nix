{
  config,
  lib,
  pkgs,
  ...
}:

{
  backup.backups.root = {
    paths = [
      "/root"
    ];
    extraBackupArgs = [
      "--exclude=/root/.cache"
    ];
  };

  backup.backups.home = {
    paths = [
      "/home/petrtsopa"
    ];
    extraBackupArgs = [
      "--exclude=/home/petrtsopa/.cache"
      "--exclude=/home/petrtsopa/.vscode-server"
      "--exclude=/home/petrtsopa/.cursor-server"
      "--exclude=/home/petrtsopa/.vscode-remote-containers"
    ];
  };
}
