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

  backup.defaultTo = [
    "local"
    "yandex"
  ];

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
    local = {
      type = "local";
      path = "/mnt/data/backups";
    };
    local-minecraft = {
      type = "local";
      path = "/mnt/data/minecraft-backups";
    };
  };

  systemd.services.cleanup-script = {
    description = "Cleanup script";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      bash
      curl
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${config.age.secrets.cleanup-script.path}";
    };
  };

  systemd.timers.cleanup-script = {
    description = "Run cleanup-script weekly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 06:30";
      RandomizedDelaySec = "15m";
      Persistent = true;
      AccuracySec = "5m";
    };
  };

  age.secrets = {
    restic-key = {
      file = ../secrets/restic-key.age;
    };
    rclone-config = {
      file = ../secrets/rclone-config.age;
    };
    cleanup-script = {
      file = ../secrets/cleanup-script.age;
    };
  };
}
