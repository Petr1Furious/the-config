{
  config,
  lib,
  pkgs,
  ...
}:

let
  mkSingBoxSecret = file: {
    file = ./secrets/${file}.age;
    path = "/run/sing-box-configs/${file}.json";
    mode = "440";
    owner = "nginx";
    group = "nginx";
  };

  singBoxSecretFiles = [ "sing-box-proxy-all" ];
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
  };

  traefik.proxies = [
    {
      host = "petr1furious.me";
      target = "http://127.0.0.1:${toString config.setup.nginxPort}";
    }
  ];

  age.secrets =
    {
      htpasswd = {
        file = ./secrets/htpasswd.age;
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
