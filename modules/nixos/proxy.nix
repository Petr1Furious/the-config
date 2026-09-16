{
  config,
  lib,
  pkgs-unstable,
  pkgs,
  secrets,
  ...
}:

let
  fetchCreds = config.age.secrets."sing-box-fetch".path;

  mkInstance =
    name: instance:
    let
      singBoxStateDir = "/var/lib/${name}";
      singBoxConfigUpdatedMarker = "${singBoxStateDir}/.config-updated";

      singBoxProxySyncScript = pkgs.writeShellScript "${name}-proxy-sync" ''
        set -euo pipefail

        url="${instance.generatorUrl}"
        out="${singBoxStateDir}/config.json"
        marker="${singBoxConfigUpdatedMarker}"
        tmp="$(${pkgs.coreutils}/bin/mktemp)"

        cleanup() {
          ${pkgs.coreutils}/bin/rm -f "$tmp"
        }
        trap cleanup EXIT

        # Basic-auth credentials are "<user>:<password>". Pass them through a curl
        # config on stdin so they never appear in the process list.
        creds="$(${pkgs.coreutils}/bin/cat ${fetchCreds})"
        ${pkgs.curl}/bin/curl -fsS --retry 5 --retry-delay 5 --retry-connrefused \
          --config <(${pkgs.coreutils}/bin/printf 'user = "%s"\n' "$creds") \
          "$url" -o "$tmp"
        ${lib.getExe pkgs-unstable.sing-box} check -c "$tmp"

        if [[ ! -f "$out" ]] || ! ${pkgs.diffutils}/bin/cmp -s "$tmp" "$out"; then
          ${pkgs.coreutils}/bin/mv "$tmp" "$out"
          trap - EXIT
          ${pkgs.coreutils}/bin/touch "$marker"
        fi
      '';

      singBoxProxySyncPostScript = pkgs.writeShellScript "${name}-proxy-sync-post" ''
        set -euo pipefail

        marker="${singBoxConfigUpdatedMarker}"
        if [[ -f "$marker" ]]; then
          ${pkgs.coreutils}/bin/rm -f "$marker"
          ${pkgs.systemd}/bin/systemctl --no-block restart ${name}.service
        fi
      '';
    in
    {
      services."${name}-proxy-sync" = {
        description = "Sync ${name} proxy config from the generator";
        before = [ "${name}.service" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = name;
          StateDirectoryMode = "0700";
          ExecStart = singBoxProxySyncScript;
          ExecStartPost = singBoxProxySyncPostScript;
        };
        wantedBy = [ "multi-user.target" ];
      };

      timers."${name}-proxy-sync" = {
        description = "Periodically re-sync ${name} proxy config";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 00/4:00:00";
          Persistent = true;
        };
      };

      services.${name} = {
        after = [
          "network-online.target"
          "${name}-proxy-sync.service"
        ];
        wants = [
          "network-online.target"
          "${name}-proxy-sync.service"
        ];
        unitConfig = {
          ConditionPathExists = "${singBoxStateDir}/config.json";
        };
        serviceConfig = {
          StateDirectory = name;
          StateDirectoryMode = "0700";
          Restart = "on-failure";
          RestartSec = "1min";
          ExecStart = "${lib.getExe pkgs-unstable.sing-box} -D \${STATE_DIRECTORY} -c \${STATE_DIRECTORY}/config.json run";
        };
        wantedBy = [ "multi-user.target" ];
      };
    };

  instances = lib.mapAttrsToList mkInstance config.proxy.instances;
in
{
  options.proxy.instances = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.generatorUrl = lib.mkOption {
          type = lib.types.str;
          description = ''
            URL of a sing-box proxy config served by the generator on the OVH
            server, behind HTTP basic auth.
          '';
        };
      }
    );
    description = ''
      sing-box proxy instances, keyed by the name of their systemd unit and
      state directory. Each pulls its own config from the generator.
    '';
  };

  config = {
    proxy.instances.sing-box.generatorUrl = lib.mkDefault "https://petr1furious.me/sing-box/server-proxy.json";

    age.secrets."sing-box-fetch".file = secrets + "/sing-box-fetch.age";

    systemd.services = lib.mkMerge (map (instance: instance.services) instances);
    systemd.timers = lib.mkMerge (map (instance: instance.timers) instances);
  };
}
