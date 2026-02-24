{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkSingBoxSecret = file: {
    file = ../secrets/${file}.age;
    path = "/run/sing-box-configs/${file}.json";
    mode = "440";
    owner = "nginx";
    group = "nginx";
  };

  singBoxSecretFiles = [
    "sing-box-proxy-blocked"
    "sing-box-proxy-all-except-ru"
    "sing-box-proxy-all"
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

    locations."/sing-box/" = {
      alias = "/run/sing-box-configs/";
      basicAuthFile = config.age.secrets.htpasswd.path;
      extraConfig = ''
        autoindex on;
      '';
    };

    locations."/sing-box/generate" = {
      proxyPass = "http://127.0.0.1:${toString singBoxGeneratorPort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };

    locations."/xray" = {
      proxyPass = "http://127.0.0.1:${toString xrayGeneratorPort}";
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };

  systemd.services.xray-config-generator = {
    description = "XRAY config templating HTTP server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.python3} ${xrayCfgGenerator} --file ${xrayCfgBase} --host 127.0.0.1 --port ${toString xrayGeneratorPort} --path /xray";
      Restart = "on-failure";
      DynamicUser = true;
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

  age.secrets = {
    htpasswd = {
      file = ../secrets/htpasswd.age;
      mode = "440";
      owner = "nginx";
      group = "nginx";
    };
  }
  // builtins.listToAttrs (
    map (name: {
      inherit name;
      value = mkSingBoxSecret name;
    }) singBoxSecretFiles
  );
}
