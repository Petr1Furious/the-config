{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

let
  hostName = "immich.petr1furious.me";
in
{
  services.immich = {
    enable = true;
    mediaLocation = "/srv/immich";
    settings = {
      server.externalDomain = "https://${hostName}";
      machineLearning.ocr.modelName = "ESLAV__PP-OCRv5_mobile";
    };
    package = pkgs-unstable.immich;
  };

  traefik.proxies = [
    {
      host = hostName;
      target = "http://localhost:${toString config.services.immich.port}";
    }
  ];

  backup.locations.immich = {
    from = [
      "/srv/immich"
    ];
  };
}
