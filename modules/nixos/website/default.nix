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
  # Curated gate set kept small: the backend issues short-lived per-connect
  # credentials, so the config is regenerated on demand and each pull dials only
  # these gates, keeping upstream connect volume close to app-like usage.
  meowconnectGates = "Best server,Netherlands,Finland,Sweden,Germany,Poland,Russia";

  allExceptRu = {
    routing = "all-except-ru";
  };
  blocked = {
    routing = "blocked";
  };
  ruOnly = {
    routing = "ru-only";
  };
  allIncludingRu = {
    routing = "all-including-ru";
  };
  serverProxy = {
    routing = "all-including-ru";
    inbound = "proxy";
    servers = "Netherlands";
  };
  browserProxy = {
    routing = "all-including-ru";
    inbound = "proxy";
    servers = "Denmark";
    socks_port = 10818;
    http_port = 10819;
    allow_ads = true;
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
    "browser-proxy.json" = browserProxy;

    "all-including-ru.json" = allIncludingRu;
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
      ExecStart = "${lib.getExe pkgs.python3} ${singBoxCfgGenerator} --file ${singBoxCfgBase} --shortcuts-file ${singBoxShortcutsFile} --state-dir ${meowconnectStateDir} --host 127.0.0.1 --port ${toString singBoxGeneratorPort} --path /sing-box/generate --gates ${lib.escapeShellArg meowconnectGates} --cache-ttl 180";
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

  # No periodic refresh service: credentials are short-lived, so the generator
  # regenerates on demand per request (with a short coalescing TTL). A timed
  # cache would be stale almost always.

  caddy.proxies = [
    {
      host = "petr1furious.me";
      target = "http://127.0.0.1:${toString config.setup.nginxPort}";
    }
  ];

  age.secrets.htpasswd = mkNginxSecret "htpasswd";
  age.secrets.meowconnect-env = mkMeowSecret "meowconnect-env";
}
