{
  config,
  lib,
  pkgs,
  ...
}:

let
  hostName = "immich.petr1furious.me";
in
{
  services.immich = {
    enable = true;
    mediaLocation = "/srv/immich";
    settings.server.externalDomain = "https://${hostName}";
  };

  traefik.proxies = [
    {
      host = hostName;
      target = "http://localhost:${toString config.services.immich.port}";
    }
  ];

  backup.backups.immich = {
    paths = [
      "/srv/immich"
    ];
  };
}
