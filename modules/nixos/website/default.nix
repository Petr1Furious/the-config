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
  singBoxCfgBase114 = ./sing-box-config-base-1.11.4.json;
  singBoxCfgGenerator = ./sing-box-config-generator.py;

  websiteRoot = ./.;
  meowconnectStateDir = "/var/lib/meowconnect";
  meowconnectUser = "meowconnect";

  allExceptRu = {
    routing = "all-except-ru";
  };
  allExceptRuLegacy = allExceptRu // {
    legacy = true;
  };
  blocked = {
    routing = "blocked";
  };
  blockedLegacy = blocked // {
    legacy = true;
  };
  ruOnly = {
    routing = "ru-only";
  };
  ruOnlyLegacy = ruOnly // {
    legacy = true;
  };
  serverProxy = allExceptRu // {
    inbound = "proxy";
    proxy_public = true;
    servers = "Netherlands";
  };
  singBoxShortcuts = {
    "all-except-ru.json" = allExceptRu;
    "all.json" = allExceptRu;
    "simple-all.json" = allExceptRu;
    "sing-box-proxy-all-except-ru.json" = allExceptRu;

    "all-except-ru-legacy.json" = allExceptRuLegacy;
    "all-legacy.json" = allExceptRuLegacy;
    "simple-all-legacy.json" = allExceptRuLegacy;

    "blocked.json" = blocked;
    "simple-blocked.json" = blocked;
    "sing-box-proxy-blocked.json" = blocked;

    "blocked-legacy.json" = blockedLegacy;
    "simple-blocked-legacy.json" = blockedLegacy;

    "ru-only.json" = ruOnly;
    "ru-only-legacy.json" = ruOnlyLegacy;
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
      ExecStart = "${lib.getExe pkgs.python3} ${singBoxCfgGenerator} --file ${singBoxCfgBase} --legacy-file ${singBoxCfgBase114} --shortcuts-file ${singBoxShortcutsFile} --state-dir ${meowconnectStateDir} --host 127.0.0.1 --port ${toString singBoxGeneratorPort} --path /sing-box/generate";
      Environment = "PYTHONPATH=${websiteRoot}";
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
