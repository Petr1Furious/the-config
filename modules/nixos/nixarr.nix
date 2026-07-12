{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  proxyPort = 10809;

  proxyEnv = {
    HTTP_PROXY = "http://127.0.0.1:${toString proxyPort}";
    HTTPS_PROXY = "http://127.0.0.1:${toString proxyPort}";
    NO_PROXY = "localhost,127.0.0.1";
  };
in
{
  imports = [ inputs.nixarr.nixosModules.default ];

  services.flaresolverr.enable = true;

  nixarr = {
    enable = true;

    jellyfin.enable = true;
    radarr.enable = true;
    sonarr.enable = true;
    prowlarr.enable = true;
    transmission = {
      enable = true;

      extraSettings = {
        ratio-limit-enabled = true;
        ratio-limit = 1;

        idle-seeding-limit-enabled = true;
        idle-seeding-limit = 1440;
      };
    };

    mediaDir = "/srv/media";
    stateDir = "/srv/media/.state/nixarr";
  };

  services.radarr = {
    settings = {
      server.port = 7878;
    };
  };

  services.sonarr = {
    settings = {
      server.port = 8989;
    };
  };

  systemd.services = {
    # radarr.environment = proxyEnv;
    # sonarr.environment = proxyEnv;
    # prowlarr.environment = proxyEnv;
    transmission.environment = proxyEnv;
  };

  backup.locations.nixarr = {
    from = [
      "/srv/media/.state/nixarr"
    ];
  };

  caddy.proxies = [
    {
      host = "jellyfin.petr1furious.me";
      target = "http://127.0.0.1:8096";
    }
    {
      host = "radarr.petr1furious.me";
      target = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
    }
    {
      host = "sonarr.petr1furious.me";
      target = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
    }
  ];
}
