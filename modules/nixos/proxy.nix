{
  config,
  lib,
  pkgs-unstable,
  pkgs,
  secrets,
  ...
}:

let
  cfg = config.proxy;
  singBoxStateDir = "/var/lib/sing-box";
  singBoxConfigUpdatedMarker = "${singBoxStateDir}/.config-updated";

  fetchCreds = config.age.secrets."sing-box-fetch".path;

  singBoxProxySyncScript = pkgs.writeShellScript "sing-box-proxy-sync" ''
    set -euo pipefail

    url="${cfg.generatorUrl}"
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

  singBoxProxySyncPostScript = pkgs.writeShellScript "sing-box-proxy-sync-post" ''
    set -euo pipefail

    marker="${singBoxConfigUpdatedMarker}"
    if [[ -f "$marker" ]]; then
      ${pkgs.coreutils}/bin/rm -f "$marker"
      ${pkgs.systemd}/bin/systemctl --no-block restart sing-box.service
    fi
  '';
in
{
  options.proxy.generatorUrl = lib.mkOption {
    type = lib.types.str;
    default = "https://petr1furious.me/sing-box/server-proxy.json";
    description = ''
      URL of the sing-box server-proxy config served by the generator on the
      new server, behind HTTP basic auth. Fetched by every host running this
      module, so both the home box and the OVH box pull the same config from
      the OVH generator.
    '';
  };

  config = {
    age.secrets."sing-box-fetch".file = secrets + "/sing-box-fetch.age";

    systemd.services.sing-box-proxy-sync = {
      description = "Sync sing-box proxy config from the generator";
      before = [ "sing-box.service" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "sing-box";
        StateDirectoryMode = "0700";
        ExecStart = singBoxProxySyncScript;
        ExecStartPost = singBoxProxySyncPostScript;
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.timers.sing-box-proxy-sync = {
      description = "Periodically re-sync sing-box proxy config";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 00/4:00:00";
        Persistent = true;
      };
    };

    systemd.services.sing-box = {
      after = [
        "network-online.target"
        "sing-box-proxy-sync.service"
      ];
      wants = [
        "network-online.target"
        "sing-box-proxy-sync.service"
      ];
      unitConfig = {
        ConditionPathExists = "${singBoxStateDir}/config.json";
      };
      serviceConfig = {
        StateDirectory = "sing-box";
        StateDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = "1min";
        ExecStart = "${lib.getExe pkgs-unstable.sing-box} -D \${STATE_DIRECTORY} -c \${STATE_DIRECTORY}/config.json run";
      };
      wantedBy = [ "multi-user.target" ];
    };

    networking.firewall.allowedTCPPorts = [
      10808
      10809
    ];
  };
}
