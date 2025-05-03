{
  config,
  lib,
  pkgs,
  ...
}:

{
  virtualisation.compositor.tgauth = {
    services = {
      main = {
        container_name = "tgauth";
        environment = [
          "SERVER_BASE=https://mc-auth.petr1furious.me/"
          "YGG_KEY_PATH=/config/key.der"
        ];
        extra_hosts = [ "host.docker.internal:host-gateway" ];
        image = "registry.vanutp.dev/minecraft/tgauth-backend:latest";
        labels = [
          "traefik.enable=true"
          "traefik.http.routers.tgauth.rule=Host(`mc-auth.petr1furious.me`)"
        ];
        restart = "always";
        volumes = [
          "/srv/tgauth-data:/data"
          "${config.age.secrets.tgauth-key.path}:/config/key.der"
        ];
        env_file = config.age.secrets.tgauth-env.path;
      };
    };
  };

  age.secrets.tgauth-key = {
    file = ../../../secrets/tgauth-key.age;
  };
  age.secrets.tgauth-env = {
    file = ../../../secrets/tgauth-env.age;
  };

  services.postgresql.ensureDatabases = [ "tgauth" ];
  services.postgresql.ensureUsers = [
    {
      name = "tgauth";
      ensureDBOwnership = true;
    }
  ];

  backup.backups.tgauth.paths = [ "/srv/tgauth-data" ];
}
