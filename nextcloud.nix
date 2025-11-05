{
  config,
  lib,
  pkgs,
  ...
}:

let
  hostName = "nextcloud.petr1furious.me";
  nextCloudHome = "/srv/nextcloud";
in
{
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud31;
    hostName = hostName;
    home = nextCloudHome;
    maxUploadSize = "16G";
    database.createLocally = true;
    configureRedis = true;
    https = true;

    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps)
        news
        contacts
        calendar
        tasks
        ;
    };

    config = {
      adminuser = "root";
      adminpassFile = config.age.secrets.nextcloud-admin-password.path;
      dbtype = "pgsql";
    };

    phpOptions = {
      "opcache.interned_strings_buffer" = 32;
    };

    settings = {
      trusted_proxies = [
        "127.0.0.1"
        "::1"
      ];
      overwriteprotocol = "https";
      maintenance_window_start = 3;
      enabledPreviewProviders = [
        "OC\\Preview\\BMP"
        "OC\\Preview\\GIF"
        "OC\\Preview\\JPEG"
        "OC\\Preview\\Krita"
        "OC\\Preview\\MarkDown"
        "OC\\Preview\\MP3"
        "OC\\Preview\\OpenDocument"
        "OC\\Preview\\PNG"
        "OC\\Preview\\TXT"
        "OC\\Preview\\XBitmap"
        "OC\\Preview\\HEIC"
      ];
    };
  };

  traefik.proxies = [
    {
      host = hostName;
      target = "http://localhost:${toString config.setup.nginxPort}";
    }
  ];

  backup.locations.nextcloud = {
    from = [
      nextCloudHome
    ];
  };

  age.secrets.nextcloud-admin-password = {
    file = ./secrets/nextcloud-admin-password.age;
    mode = "440";
    owner = "nextcloud";
    group = "nextcloud";
  };

  services.nginx.virtualHosts.${hostName}.extraConfig = ''
    add_header X-XSS-Protection "1; mode=block" always;
  '';
}
