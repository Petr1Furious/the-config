{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./services/traefik
    ./services/tgauth
    ./services/overleaf
    ./services/pterodactyl
  ];

  options = with lib; {
    virtualisation.compositor = mkOption {
      type = types.attrs;
      default = { };
    };
  };

  config =
    let
      systemdUnits = lib.attrsets.mapAttrs' (name: content: {
        name = "docker-compose-" + name;
        value =
          let
            composeFile = pkgs.writers.writeYAML "docker-compose-${name}.yml" content;

          in
          {
            description = "Docker Compose service for " + name;
            after = [
              "docker.service"
            ];
            requires = [
              "docker.service"
            ];
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.docker ];
            script = ''
              docker compose --project-name ${name} -f ${composeFile} up -d --remove-orphans
            '';
            serviceConfig = {
              Type = "oneshot";
              WorkingDirectory = "/var/empty";
            };
          };
      }) config.virtualisation.compositor;

    in
    {
      virtualisation.docker.enable = true;
      virtualisation.oci-containers.backend = "docker";

      systemd.services = systemdUnits;
    };
}
