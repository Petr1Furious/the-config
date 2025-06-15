{ config, lib, ... }:
let
  rcloneConfigFile = config.age.secrets.rclone-config.path;
  passwordFile = config.age.secrets.restic-key.path;
in
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
                    repository = mkOption {
                      type = types.str;
                      default = "rclone:yandex:/backups";
                      description = "Restic repository to use";
                    };
                    tag = mkOption {
                      type = types.str;
                      default = name;
                      description = "Tag to identify and organize snapshots";
                    };
                    paths = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                      description = "Files and directories to back up";
                    };
                    dynamicFilesFrom = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Command to output a list of files to back up";
                    };
                    extraBackupArgs = mkOption {
                      type = types.listOf types.str;
                      default = [ ];
                      description = "Additional arguments to pass to the restic backup command";
                    };
                    retryLock = mkOption {
                      type = types.nullOr types.str;
                      default = "10m";
                      description = "Retry to lock the repository if it is already locked, takes a value like 5m or 2h";
                    };
                    stuckRequestTimeout = mkOption {
                      type = types.nullOr types.str;
                      default = "2m0s";
                      description = "Duration after which to retry stuck requests";
                    };
                    backupPrepareCommand = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Command to run before starting the backup";
                    };
                    backupCleanupCommand = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Command to run after completing the backup";
                    };
                    schedule = mkOption {
                      type = types.str;
                      default = "00/8:00:00";
                      description = "When to run the backup, using systemd calendar syntax";
                    };
                    randomizedDelay = mkOption {
                      type = types.str;
                      default = "1h";
                      description = "Random delay to add to backup start time to prevent multiple backups starting simultaneously";
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
        inherit rcloneConfigFile;
        inherit passwordFile;
        extraBackupArgs =
          [
            "--tag=${cfg.tag}"
          ]
          ++ lib.optionals (cfg.retryLock != null) [
            "--retry-lock=${cfg.retryLock}"
          ]
          ++ lib.optionals (cfg.stuckRequestTimeout != null) [
            "--stuck-request-timeout=${cfg.stuckRequestTimeout}"
          ]
          ++ cfg.extraBackupArgs;
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
          repository
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
