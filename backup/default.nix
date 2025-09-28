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

  backup.enable = true;
  backup.rcloneConfigPath = config.age.secrets.rclone-config.path;
  backup.passwordFilePath = config.age.secrets.restic-key.path;

  backup.defaultTo = [ "yandex" ];

  backup.global.options.all = {
    "retry-lock" = "5m";
  };

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
