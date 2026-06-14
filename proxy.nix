{
  config,
  lib,
  pkgs-unstable,
  pkgs,
  ...
}:

let
  singBoxGeneratorPort = 18081;
  singBoxStateDir = "/var/lib/sing-box";
  singBoxConfigUpdatedMarker = "${singBoxStateDir}/.config-updated";

  singBoxProxySyncScript = pkgs.writeShellScript "sing-box-proxy-sync" ''
    set -euo pipefail

    url="http://127.0.0.1:${toString singBoxGeneratorPort}/sing-box/server-proxy.json"
    out="${singBoxStateDir}/config.json"
    marker="${singBoxConfigUpdatedMarker}"
    tmp="$(${pkgs.coreutils}/bin/mktemp)"

    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.curl}/bin/curl -fsS "$url" -o "$tmp"
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
      ${pkgs.systemd}/bin/systemctl restart sing-box.service
    fi
  '';
in
{
  systemd.services.sing-box-proxy-sync = {
    description = "Sync local sing-box proxy config from generator";
    before = [ "sing-box.service" ];
    after = [
      "network-online.target"
      "sing-box-config-generator.service"
      "meowconnect-outbounds.service"
    ];
    wants = [
      "network-online.target"
      "sing-box-config-generator.service"
      "meowconnect-outbounds.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = singBoxProxySyncScript;
      ExecStartPost = singBoxProxySyncPostScript;
    };
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.sing-box = {
    after = [
      "network-online.target"
      "sing-box-proxy-sync.service"
    ];
    requires = [ "sing-box-proxy-sync.service" ];
    wants = [ "network-online.target" ];
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
}
