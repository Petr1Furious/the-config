{
  config,
  lib,
  pkgs,
  ...
}:

{
  age.secrets.vaultwarden-admin-token = {
    file = ../../../secrets/vaultwarden-admin-token.age;
  };

  virtualisation.compositor.vaultwarden = {
    services = {
      vaultwarden = {
        container_name = "vaultwarden";
        image = "vaultwarden/server:latest";
        labels = [
          "traefik.enable=true"
          "traefik.http.routers.vaultwarden.rule=Host(`vaultwarden.petr1furious.me`)"
        ];
        restart = "unless-stopped";
        volumes = [ "/srv/vaultwarden:/data" ];
        environment = {
          SIGNUPS_ALLOWED = false;
          DOMAIN = "https://vaultwarden.petr1furious.me";
        };
        env_file = config.age.secrets.vaultwarden-admin-token.path;
      };
    };
  };

  backup.backups.vaultwarden.paths = [ "/srv/vaultwarden" ];
}
