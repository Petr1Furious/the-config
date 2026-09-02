{
  config,
  lib,
  pkgs,
  secrets,
  ...
}:

let
  mkNginxSecret = file: {
    file = secrets + "/${file}.age";
    mode = "440";
    owner = "nginx";
    group = "nginx";
  };

  singBoxGeneratorPort = 18081;
  singBoxCfgBase = ./sing-box-config-base.json;
  singBoxCfgGenerator = ./sing-box-config-generator.py;

  websiteRoot = ./.;
  meowconnectStateDir = "/var/lib/meowconnect";
  meowconnectUser = "meowconnect";

  allExceptRu = {
    routing = "all-except-ru";
  };
  blocked = {
    routing = "blocked";
  };
  ruOnly = {
    routing = "ru-only";
  };
  serverProxy = {
    routing = "all-including-ru";
    inbound = "proxy";
    servers = "Netherlands";
  };
  singBoxShortcuts = {
    "all-except-ru.json" = allExceptRu;
    "all.json" = allExceptRu;
    "simple-all.json" = allExceptRu;
    "sing-box-proxy-all-except-ru.json" = allExceptRu;

    "blocked.json" = blocked;
    "simple-blocked.json" = blocked;
    "sing-box-proxy-blocked.json" = blocked;

    "ru-only.json" = ruOnly;
    "server-proxy.json" = serverProxy;
  };
  singBoxShortcutsFile = pkgs.writeText "sing-box-shortcuts.json" (builtins.toJSON singBoxShortcuts);

  mkMeowSecret = file: {
    file = secrets + "/${file}.age";
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

  users.groups.${meowconnectUser} = { };
  users.users.${meowconnectUser} = {
    isSystemUser = true;
    group = meowconnectUser;
  };

  systemd.tmpfiles.rules = [
    "d ${meowconnectStateDir} 0750 ${meowconnectUser} ${meowconnectUser} -"
  ];

  systemd.services.sing-box-config-generator = {
    description = "sing-box config templating HTTP server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.python3} ${singBoxCfgGenerator} --file ${singBoxCfgBase} --shortcuts-file ${singBoxShortcutsFile} --state-dir ${meowconnectStateDir} --host 127.0.0.1 --port ${toString singBoxGeneratorPort} --path /sing-box/generate";
      Environment = [
        "PYTHONPATH=${websiteRoot}"
        "PYTHONUNBUFFERED=1"
      ];
      WorkingDirectory = "${websiteRoot}";
      EnvironmentFile = config.age.secrets.meowconnect-env.path;
      Restart = "on-failure";
      User = meowconnectUser;
      Group = meowconnectUser;
    };
  };

  systemd.services.sing-box-config-generator-refresh = {
    description = "Refresh raw MeowConnect responses";
    after = [ "sing-box-config-generator.service" ];
    requires = [ "sing-box-config-generator.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.curl} -fsS -X POST http://127.0.0.1:${toString singBoxGeneratorPort}/sing-box-refresh/";
      ExecStartPost = "${pkgs.systemd}/bin/systemctl start sing-box-proxy-sync.service";
    };
  };

  systemd.timers.sing-box-config-generator-refresh = {
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
