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

  singBoxSecretFiles = [
    "htpasswd"
    "htpasswd-admin"
    "sing-box-simple-blocked"
    "sing-box-simple-all"
    "sing-box-blocked"
    "sing-box-all"
  ];

  xrayGeneratorPort = 18080;
  xrayCfgBase = ./xray-config-base.json;
  xrayCfgGenerator = ./xray-config-generator.py;
  singBoxGeneratorPort = 18081;
  singBoxCfgBase = ./sing-box-config-base.json;
  singBoxCfgGenerator = ./sing-box-config-generator.py;
in
{
  services.nginx.virtualHosts."petr1furious.me" = {
    locations."/" = {
      return = "302 https://www.youtube.com/watch?v=dQw4w9WgXcQ";
    };

    locations."= /sing-box" = {
      return = "302 /sing-box/";
    };

    locations."/sing-box/generate" = {
      proxyPass = "http://127.0.0.1:${toString singBoxGeneratorPort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };

    locations."= /sing-box/simple-blocked.json" = {
      basicAuthFile = config.age.secrets.htpasswd.path;
      extraConfig = ''
        include ${config.age.secrets.sing-box-simple-blocked.path};
      '';
    };

    locations."= /sing-box/simple-all.json" = {
      basicAuthFile = config.age.secrets.htpasswd.path;
      extraConfig = ''
        include ${config.age.secrets.sing-box-simple-all.path};
      '';
    };

    # backward compatibility
    locations."= /sing-box/sing-box-proxy-blocked.json" = {
      basicAuthFile = config.age.secrets.htpasswd.path;
      extraConfig = ''
        include ${config.age.secrets.sing-box-simple-blocked.path};
      '';
    };

    # backward compatibility
    locations."= /sing-box/sing-box-proxy-all-except-ru.json" = {
      basicAuthFile = config.age.secrets.htpasswd.path;
      extraConfig = ''
        include ${config.age.secrets.sing-box-simple-all.path};
      '';
    };

    locations."= /sing-box/blocked.json" = {
      basicAuthFile = config.age.secrets.htpasswd-admin.path;
      extraConfig = ''
        include ${config.age.secrets.sing-box-blocked.path};
      '';
    };

    locations."= /sing-box/all.json" = {
      basicAuthFile = config.age.secrets.htpasswd-admin.path;
      extraConfig = ''
        include ${config.age.secrets.sing-box-all.path};
      '';
    };
  };

  systemd.services.sing-box-config-generator = {
    description = "sing-box config templating HTTP server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.python3} ${singBoxCfgGenerator} --file ${singBoxCfgBase} --host 127.0.0.1 --port ${toString singBoxGeneratorPort} --path /sing-box/generate";
      Restart = "on-failure";
      DynamicUser = true;
    };
  };

  caddy.proxies = [
    {
      host = "petr1furious.me";
      target = "http://127.0.0.1:${toString config.setup.nginxPort}";
    }
  ];
  age.secrets = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = mkNginxSecret name;
    }) singBoxSecretFiles
  );
}
