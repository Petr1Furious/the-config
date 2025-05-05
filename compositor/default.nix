{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./services/traefik
    ./services/minecraft/hserver
    ./services/vaultwarden
    ./services/tgauth
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
              "docker-network-monitoring.service"
            ];
            requires = [
              "docker.service"
              "docker-network-monitoring.service"
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

      systemd.services = lib.mkMerge [
        systemdUnits
        {
          docker-network-monitoring = {
            description = "Create Docker network 'monitoring'";
            wantedBy = [ "multi-user.target" ];
            after = [ "docker.service" ];
            requires = [ "docker.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              ${lib.getExe pkgs.docker} network inspect monitoring >/dev/null 2>&1 || \
              ${lib.getExe pkgs.docker} network create monitoring
            '';
          };
        }
      ];
    };
}
