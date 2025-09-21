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

  age.secrets.sing-box-http-proxy = {
    file = ./secrets/sing-box-http-proxy.age;
  };
}
