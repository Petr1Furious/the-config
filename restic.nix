{ config, lib, ... }:
{
  options = with lib; {
    backup = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
          };
          backups = mkOption {
            type = types.attrsOf (
              types.submodule (
                { name, ... }:
                {
                  options = {
                    tag = mkOption {
                      type = types.str;
                      default = name;
                    };
                    paths = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                    };
                    dynamicFilesFrom = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    extraBackupArgs = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                    };
                    backupPrepareCommand = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    backupCleanupCommand = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                    };
                    schedule = mkOption {
                      type = types.str;
                      default = "00/8:00:00";
                    };
                    randomizedDelay = mkOption {
                      type = types.str;
                      default = "1h";
                    };
                  };
                }
              )
            );
          };
        };
      };
      default = { };
    };
  };
  config = {
    services.restic.backups = lib.mkIf config.backup.enable (
      lib.mapAttrs (name: cfg: {
        initialize = true;
        repository = "rclone:yandex:/backups";
        rcloneConfigFile = config.age.secrets.rclone-config.path;
        passwordFile = config.age.secrets.restic-key.path;
        extraBackupArgs = [ "--tag=${cfg.tag}" ] ++ cfg.extraBackupArgs;
        pruneOpts = [
          "--keep-last=10"
          "--keep-daily=7"
          "--keep-weekly=4"
          "--tag=${cfg.tag}"
          "--host=${config.networking.hostName}"
        ];
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = cfg.randomizedDelay;
        };
        inherit (cfg)
          paths
          dynamicFilesFrom
          backupPrepareCommand
          backupCleanupCommand
          ;
      }) config.backup.backups
    );

    age.secrets = lib.mkIf config.backup.enable {
      restic-key = {
        file = ./secrets/restic-key.age;
      };
      rclone-config = {
        file = ./secrets/rclone-config.age;
      };
    };
  };
}
