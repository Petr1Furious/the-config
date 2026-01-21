{
  config,
  lib,
  pkgs,
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
  nixarr = {
    enable = true;

    jellyfin.enable = true;
    radarr.enable = true;
    sonarr.enable = true;
    prowlarr.enable = true;
    transmission.enable = true;

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
    radarr.environment = proxyEnv;
    sonarr.environment = proxyEnv;
    prowlarr.environment = proxyEnv;
    # transmission.environment = proxyEnv;
  };

  backup.locations.nixarr = {
    from = [
      "/srv/media/.state/nixarr"
    ];
  };

  traefik.proxies = [
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
