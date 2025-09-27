{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./autorestic.nix
  ];

  systemd.tmpfiles.rules = [
    "d /srv/autorestic 0750 root root -"
  ];

  backup.enable = true;
  backup.rcloneConfigPath = config.age.secrets.rclone-config.path;
  backup.passwordFilePath = config.age.secrets.restic-key.path;

  backup.backends = {
    yandex = {
      type = "rclone";
      path = "yandex:/backups";
    };
    yandex-minecraft = {
      type = "rclone";
      path = "yandex:/minecraft-backups";
    };
  };

  age.secrets = {
    restic-key = {
      file = ../secrets/restic-key.age;
    };
    rclone-config = {
      file = ../secrets/rclone-config.age;
    };
  };
}
