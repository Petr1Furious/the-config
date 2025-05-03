{
  config,
  lib,
  pkgs,
  ...
}:
{
  options = with lib; {
    traefik.proxies = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            host = mkOption { type = types.str; };
            target = mkOption { type = types.str; };
          };
        }
      );
      default = [ ];
    };
  };

  config =
    let
      rulesFile = (pkgs.formats.yaml { }).generate "rules.yml" (
        if (config.traefik.proxies != [ ]) then
          {
            http = builtins.foldl' (a: b: lib.recursiveUpdate a b) { } (
              map (
                entry:
                let
                  entryId = builtins.replaceStrings [ "." ] [ "__" ] entry.host;
                in
                {
                  routers.${entryId} = {
                    service = entryId;
                    rule = "Host(`${entry.host}`)";
                  };
                  services.${entryId}.loadBalancer.servers = [ { url = entry.target; } ];
                }
              ) config.traefik.proxies
            );
          }
        else
          { }
      );
    in
    {
      virtualisation.compositor.traefik = {
        services = {
          traefik = {
            container_name = "traefik";
            image = "traefik:v3";
            network_mode = "host";
            restart = "unless-stopped";
            volumes = [
              "/srv/letsencrypt:/letsencrypt"
              "/var/run/docker.sock:/var/run/docker.sock:ro"
              "${./traefik.yml}:/etc/traefik/traefik.yml:ro"
              "${rulesFile}:/etc/traefik/rules.yml:ro"
            ];
            env_file = config.age.secrets.traefik-env.path;
          };
        };
      };

      age.secrets.traefik-env = {
        file = ../../../secrets/traefik-env.age;
      };
    };
}
