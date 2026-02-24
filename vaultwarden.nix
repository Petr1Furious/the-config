{
  config,
  lib,
  pkgs,
  ...
}:

let
  hostName = "vaultwarden.petr1furious.me";
  stateDirectory = "/var/lib/${config.systemd.services.vaultwarden.serviceConfig.StateDirectory}";

in
{
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN = "https://${hostName}";
      SIGNUPS_ALLOWED = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
    };
    environmentFile = config.age.secrets.vaultwarden-admin-token.path;
  };

  caddy.proxies = [
    {
      host = hostName;
      target = "http://127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
    }
  ];

  backup.locations.vaultwarden = {
    from = [
      stateDirectory
    ];
  };

  age.secrets.vaultwarden-admin-token = {
    file = ./secrets/vaultwarden-admin-token.age;
  };
}
