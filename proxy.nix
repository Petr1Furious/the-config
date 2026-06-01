{
  config,
  lib,
  pkgs-unstable,
  ...
}:

{
  systemd.services.sing-box = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      StateDirectory = "sing-box";
      StateDirectoryMode = "0700";
      Restart = "on-failure";
      RestartSec = "1min";
      ExecStart = [
        ""
        "${lib.getExe pkgs-unstable.sing-box} -D \${STATE_DIRECTORY} -c ${config.age.secrets.sing-box-proxy-config.path} run"
      ];
    };
    wantedBy = [ "multi-user.target" ];
  };

  networking.firewall.allowedTCPPorts = [
    10808
    10809
  ];

  age.secrets.sing-box-proxy-config = {
    file = ./secrets/sing-box-proxy-config.age;
  };
}
