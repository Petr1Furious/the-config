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
          "caddy=mc-auth.petr1furious.me"
          "caddy.reverse_proxy={{upstreams 8000}}"
          "caddy_ingress_network=tgauth_default"
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

  backup.locations.tgauth = {
    from = [ "/srv/tgauth-data" ];
  };
}
