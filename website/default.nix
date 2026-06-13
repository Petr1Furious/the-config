{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkNginxSecret = file: {
    file = ../secrets/${file}.age;
    mode = "440";
    owner = "nginx";
    group = "nginx";
  };

  singBoxGeneratorPort = 18081;
  singBoxCfgBase = ./sing-box-config-base.json;
  singBoxCfgBase114 = ./sing-box-config-base-1.11.4.json;
  singBoxCfgGenerator = ./sing-box-config-generator.py;
  singBoxShortcutDir = "/srv/sing-box-generator";
  singBoxGeneratorUser = "sing-box-generator";

  meowconnectPort = 18083;
  websiteRoot = ./.;
  meowconnectStateDir = "/var/lib/meowconnect";
  meowconnectUser = "meowconnect";

  mkMeowSecret = file: {
    file = ../secrets/${file}.age;
    mode = "0400";
    owner = meowconnectUser;
    group = meowconnectUser;
  };
in
{
  services.nginx.virtualHosts."petr1furious.me" = {
    locations."/" = {
      return = "302 https://www.youtube.com/watch?v=dQw4w9WgXcQ";
    };

    locations."= /sing-box" = {
      return = "302 /sing-box/";
    };

    locations."/sing-box/" = {
      basicAuthFile = config.age.secrets.htpasswd.path;
      proxyPass = "http://127.0.0.1:${toString singBoxGeneratorPort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };

  users.groups.${singBoxGeneratorUser} = { };
  users.users.${singBoxGeneratorUser} = {
    isSystemUser = true;
    group = singBoxGeneratorUser;
  };

  users.groups.${meowconnectUser} = { };
  users.users.${meowconnectUser} = {
    isSystemUser = true;
    group = meowconnectUser;
  };

  systemd.tmpfiles.rules = [
    "d ${singBoxShortcutDir} 0750 ${singBoxGeneratorUser} ${singBoxGeneratorUser} -"
    "d ${meowconnectStateDir} 0750 ${meowconnectUser} ${meowconnectUser} -"
  ];

  systemd.services.sing-box-config-generator = {
    description = "sing-box config templating HTTP server";
    after = [ "network.target" "meowconnect-outbounds.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.python3} ${singBoxCfgGenerator} --file ${singBoxCfgBase} --legacy-file ${singBoxCfgBase114} --host 127.0.0.1 --port ${toString singBoxGeneratorPort} --path /sing-box/generate --shortcut-dir ${singBoxShortcutDir} --meowconnect-url http://127.0.0.1:${toString meowconnectPort}/outbounds";
      Restart = "on-failure";
      User = singBoxGeneratorUser;
      Group = singBoxGeneratorUser;
    };
  };

  systemd.services.meowconnect-outbounds = {
    description = "MeowConnect outbound cache HTTP server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.python3} -m meowconnect.server --state-dir ${meowconnectStateDir} --host 127.0.0.1 --port ${toString meowconnectPort} --refresh-on-start";
      Environment = "PYTHONPATH=${websiteRoot}";
      WorkingDirectory = "${websiteRoot}";
      EnvironmentFile = config.age.secrets.meowconnect-env.path;
      Restart = "on-failure";
      User = meowconnectUser;
      Group = meowconnectUser;
    };
  };

  systemd.services.meowconnect-outbounds-refresh = {
    description = "Refresh MeowConnect outbound cache";
    after = [ "meowconnect-outbounds.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.curl} -fsS -X POST http://127.0.0.1:${toString meowconnectPort}/refresh";
    };
  };

  systemd.timers.meowconnect-outbounds-refresh = {
    description = "Refresh MeowConnect outbound cache every 4 hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/4:00:00";
      Persistent = true;
    };
  };

  caddy.proxies = [
    {
      host = "petr1furious.me";
      target = "http://127.0.0.1:${toString config.setup.nginxPort}";
    }
  ];

  age.secrets.htpasswd = mkNginxSecret "htpasswd";
  age.secrets.meowconnect-env = mkMeowSecret "meowconnect-env";
}
