{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

{
  systemd.services.sing-box = {
    serviceConfig = {
      StateDirectory = "sing-box";
      StateDirectoryMode = "0700";
      ExecStart = [
        ""
        "${lib.getExe pkgs-unstable.sing-box} -D \${STATE_DIRECTORY} -c ${config.age.secrets.sing-box-http-proxy.path} run"
      ];
    };
    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [
    10808
    10809
  ];

  # systemd.services.xray = {
  #   description = "Xray proxy";
  #   after = [ "network-online.target" ];
  #   wants = [ "network-online.target" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     StateDirectory = "xray";
  #     StateDirectoryMode = "0700";

  #     ExecStartPre = [
  #       (pkgs.writeShellScript "xray-update-assets" ''
  #         set -euo pipefail

  #         assets="$STATE_DIRECTORY"
  #         ${pkgs.coreutils}/bin/mkdir -p "$assets"

  #         need_fetch() {
  #           local f="$1"
  #           if [ ! -f "$f" ]; then return 0; fi
  #           local mtime now age
  #           mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$f" || echo 0)
  #           now=$(${pkgs.coreutils}/bin/date +%s)
  #           age=$(( now - mtime ))
  #           [ "$age" -ge 86400 ]
  #         }

  #         if need_fetch "$assets/geoip.dat"; then
  #           ${pkgs.curl}/bin/curl -fsSL --retry 3 -o "$assets/geoip.dat.tmp" "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/release/geoip.dat"
  #           ${pkgs.coreutils}/bin/mv "$assets/geoip.dat.tmp" "$assets/geoip.dat"
  #         fi

  #         if need_fetch "$assets/geosite.dat"; then
  #           ${pkgs.curl}/bin/curl -fsSL --retry 3 -o "$assets/geosite.dat.tmp" "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geosite/release/geosite.dat"
  #           ${pkgs.coreutils}/bin/mv "$assets/geosite.dat.tmp" "$assets/geosite.dat"
  #         fi
  #       '')
  #     ];

  #     Environment = [ "XRAY_LOCATION_ASSET=%S/xray" ];
  #     ExecStart = "${lib.getExe pkgs.xray} run -c ${config.age.secrets.xray-proxy.path}";
  #     Restart = "on-failure";
  #   };
  # };

  age.secrets.sing-box-http-proxy = {
    file = ./secrets/sing-box-http-proxy.age;
  };

  # age.secrets.xray-proxy = {
  #   file = ./secrets/xray-proxy.age;
  #   name = "xray-proxy.json";
  # };
}
