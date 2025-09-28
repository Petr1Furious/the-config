{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    mkIf
    mapAttrs
    toUpper
    replaceStrings
    foldl'
    ;

  yamlFmt = pkgs.formats.yaml { };

  toEnv = n: toUpper (replaceStrings [ "-" "." "/" ":" "@" ] [ "_" "_" "_" "_" "_" ] n);

  cfg = config.backup;

  filterNulls = attrs: lib.filterAttrs (_: v: v != null) attrs;
in
{
  options.backup = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };

    rcloneConfigPath = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    passwordFilePath = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    autoresticYamlPath = mkOption {
      type = types.str;
      default = "/srv/autorestic/autorestic.yml";
    };

    global = mkOption {
      description = "Global Autorestic settings";
      type = types.submodule {
        options = {
          forget = mkOption {
            description = "Default forget policy, location-specific nulls inherit from here";
            type = types.submodule {
              options = {
                "keep-last" = mkOption {
                  type = types.nullOr types.int;
                  default = 10;
                };
                "keep-hourly" = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                };
                "keep-daily" = mkOption {
                  type = types.nullOr types.int;
                  default = 7;
                };
                "keep-weekly" = mkOption {
                  type = types.nullOr types.int;
                  default = 4;
                };
                "keep-monthly" = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                };
                "keep-yearly" = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                };
                "keep-within" = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                };
              };
            };
            default = { };
          };

          options = mkOption {
            description = "Global restic options merged into each location";
            type = types.submodule {
              options = {
                all = mkOption {
                  type = types.attrsOf (
                    types.oneOf [
                      types.bool
                      types.int
                      types.str
                      (types.listOf types.str)
                    ]
                  );
                  default = { };
                };
                backup = mkOption {
                  type = types.attrsOf (
                    types.oneOf [
                      types.bool
                      types.int
                      types.str
                      (types.listOf types.str)
                    ]
                  );
                  default = { };
                };
              };
            };
            default = { };
          };
        };
      };
      default = { };
    };

    backends = mkOption {
      description = "Autorestic backends (keys are backend names)";
      type = types.attrsOf (
        types.submodule {
          options = {
            type = mkOption {
              type = types.str;
              description = "Backend type (e.g., rclone, local, ...)";
            };
            path = mkOption {
              type = types.str;
              description = "Backend path (e.g., backend:/backups or /mnt/disk/backup)";
            };
          };
        }
      );
      default = { };
    };

    locations = mkOption {
      description = "Autorestic locations (keys are location names)";
      type = types.attrsOf (
        types.submodule {
          options = {
            from = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };

            to = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };

            cron = mkOption {
              type = types.str;
              default = "0 8 * * *";
            };

            hooks = mkOption {
              type = types.submodule {
                options = {
                  prevalidate = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                  };
                  after = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                  };
                };
              };
              default = { };
            };

            forget = mkOption {
              type = types.str;
              default = "yes";
            };

            options = mkOption {
              type = types.submodule {
                options = {
                  all = mkOption {
                    type = types.attrsOf (
                      types.oneOf [
                        types.bool
                        types.int
                        types.str
                        (types.listOf types.str)
                      ]
                    );
                    default = { };
                  };

                  backup = mkOption {
                    type = types.attrsOf (
                      types.oneOf [
                        types.bool
                        types.int
                        types.str
                        (types.listOf types.str)
                      ]
                    );
                    default = { };
                  };

                  forget = mkOption {
                    type = types.submodule {
                      options = {
                        "keep-last" = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        "keep-hourly" = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        "keep-daily" = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        "keep-weekly" = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        "keep-monthly" = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        "keep-yearly" = mkOption {
                          type = types.nullOr types.int;
                          default = null;
                        };
                        "keep-within" = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                        };
                      };
                    };
                    default = { };
                  };
                };
              };
              default = { };
            };
          };
        }
      );
      default = { };
    };

    defaultTo = mkOption {
      description = "List of backend names used when a location does not specify 'to'.";
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = mkIf cfg.enable (
    let
      globalForget = filterNulls cfg.global.forget;
      globalAll = cfg.global.options.all;
      globalBackup = cfg.global.options.backup;

      autoresticYaml = {
        version = 2;

        global =
          { }
          // lib.optionalAttrs (globalForget != { }) { forget = globalForget; }
          // lib.optionalAttrs (globalAll != { }) { all = globalAll; }
          // lib.optionalAttrs (globalBackup != { }) { backup = globalBackup; };

        backends = mapAttrs (_: b: { inherit (b) type path; }) cfg.backends;

        locations = mapAttrs (
          _: l:
          let
            locForget = filterNulls l.options.forget;
            locOptions =
              { }
              // lib.optionalAttrs (l.options.all != { }) { all = l.options.all; }
              // lib.optionalAttrs (l.options.backup != { }) { backup = l.options.backup; }
              // lib.optionalAttrs (locForget != { }) { forget = locForget; };
            locTo = if (l.to != [ ]) then l.to else cfg.defaultTo;
          in
          {
            inherit (l) from cron;
            to = locTo;
            hooks = l.hooks;
            forget = l.forget;
            options = lib.optionalAttrs (locOptions != { }) locOptions;
          }
        ) cfg.locations;
      };

      autoresticFile = yamlFmt.generate "autorestic.yml" autoresticYaml;

      perBackendEnv = foldl' (
        acc: name:
        let
          N = toEnv name;
          backend = cfg.backends.${name};
        in
        acc
        // lib.optionalAttrs (cfg.passwordFilePath != null) {
          "AUTORESTIC_${N}_RESTIC_PASSWORD_FILE" = cfg.passwordFilePath;
        }
        // lib.optionalAttrs (backend.type == "rclone" && cfg.rcloneConfigPath != null) {
          "AUTORESTIC_${N}_RCLONE_CONFIG" = cfg.rcloneConfigPath;
        }
      ) { } (lib.attrNames cfg.backends);

      env =
        { }
        // lib.optionalAttrs (cfg.passwordFilePath != null) { RESTIC_PASSWORD_FILE = cfg.passwordFilePath; }
        // lib.optionalAttrs (cfg.rcloneConfigPath != null) { RCLONE_CONFIG = cfg.rcloneConfigPath; }
        // perBackendEnv;

      autoresticDir = builtins.dirOf cfg.autoresticYamlPath;
      autoresticLocalLock = "${autoresticDir}/.autorestic.lock.yml";

      cleanLocalLock = pkgs.writeShellScript "autorestic-clean-local-lock" ''
        set -euo pipefail
        LOCK="${autoresticLocalLock}"

        if pgrep -f "autorestic.*-c[ =]${cfg.autoresticYamlPath}" >/dev/null 2>&1; then
          exit 0
        fi

        if [ -f "$LOCK" ]; then
          if grep -qE '^[[:space:]]*running:[[:space:]]*true([[:space:]]|$)' "$LOCK"; then
            now=$(date +%s)
            mtime=$(stat -c %Y "$LOCK")
            age=$((now - mtime))
            max_age=$((2 * 60 * 60))
            if [ "$age" -gt "$max_age" ]; then
              echo "WARNING: Stale lock file found (age: ''${age}s), removing"
              rm -f "$LOCK"
            fi
          fi
        fi
      '';
    in
    {
      assertions = [
        {
          assertion = cfg.passwordFilePath != null;
          message = "backup.passwordFilePath must be set to a file path";
        }
        {
          assertion =
            (cfg.rcloneConfigPath != null)
            || (!lib.any (n: cfg.backends.${n}.type == "rclone") (lib.attrNames cfg.backends));
          message = "backup.rcloneConfigPath must be set when any backend type is 'rclone'";
        }
        {
          assertion = lib.all (b: lib.hasAttr b cfg.backends) cfg.defaultTo;
          message = "backup.defaultTo contains unknown backend name(s)";
        }
      ];

      systemd.tmpfiles.rules = [
        "d ${builtins.dirOf cfg.autoresticYamlPath} 0750 root root -"
        "L+ ${cfg.autoresticYamlPath} - - - - ${autoresticFile}"
      ];

      systemd.services.autorestic-cron = {
        description = "Autorestic cron runner";
        after = [
          "network-online.target"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = "${cleanLocalLock}";
        };
        path = [
          pkgs.autorestic
          pkgs.restic
          pkgs.rclone
          pkgs.coreutils
          pkgs.bash
          pkgs.procps
          pkgs.gnugrep
        ];
        environment = env;
        script = ''
          ${lib.getExe pkgs.autorestic} -c ${cfg.autoresticYamlPath} --ci cron --lean
        '';
      };

      systemd.timers.autorestic-cron = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitInactiveSec = "1min";
          Persistent = true;
          AccuracySec = "30s";
        };
        unitConfig.Description = "Timer for autorestic-cron";
      };

      systemd.services.autorestic-prune = {
        description = "Autorestic weekly prune";
        after = [
          "network-online.target"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          Nice = 10;
          IOSchedulingClass = "idle";
          ExecStartPre = "${cleanLocalLock}";
        };
        path = [
          pkgs.autorestic
          pkgs.restic
          pkgs.rclone
          pkgs.coreutils
          pkgs.bash
          pkgs.procps
          pkgs.gnugrep
        ];
        environment = env;
        script = ''
          ${lib.getExe pkgs.autorestic} -c ${cfg.autoresticYamlPath} --ci forget -a --prune -- --retry-lock=1h
        '';
      };

      systemd.timers.autorestic-prune = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Sun 03:30";
          RandomizedDelaySec = "15m";
          Persistent = true;
          AccuracySec = "5m";
        };
        unitConfig.Description = "Timer for autorestic-prune";
      };
    }
  );
}
