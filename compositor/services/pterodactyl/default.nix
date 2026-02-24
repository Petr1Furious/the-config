{
  config,
  lib,
  pkgs,
  ...
}:

let
  pterodactyl-wings = pkgs.stdenv.mkDerivation {
    name = "pterodactyl-wings";
    src = builtins.fetchurl {
      url = "https://github.com/pterodactyl/wings/releases/download/v1.11.13/wings_linux_amd64";
      sha256 = "sha256:06ppifap4pklcb6aldqwz6lkz2hdja5pbp8n5h4hzhgivm2zm9dc";
    };
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/wings"
    '';
    meta = with lib; {
      mainProgram = "wings";
      description = "Pterodactyl Wings";
      homepage = "https://github.com/pterodactyl/wings";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };
in
{
  virtualisation.compositor.pterodactyl = {
    services = {
      pterodactyl-db = {
        image = "mariadb:12";
        container_name = "pterodactyl-db";
        env_file = config.age.secrets.pterodactyl-db-env.path;
        volumes = [ "/srv/pterodactyl/database:/var/lib/mysql" ];
        restart = "unless-stopped";
      };

      pterodactyl-redis = {
        image = "redis:8.2-alpine";
        container_name = "pterodactyl-redis";
        restart = "unless-stopped";
      };

      pterodactyl-panel = {
        image = "ghcr.io/pterodactyl/panel:v1.11.11";
        container_name = "pterodactyl-panel";
        labels = [
          "caddy=pterodactyl.petr1furious.me"
          "caddy.reverse_proxy={{upstreams 80}}"
          "caddy_ingress_network=pterodactyl_default"
        ];
        env_file = config.age.secrets.pterodactyl-panel-env.path;
        volumes = [
          "/srv/pterodactyl/logs:/app/storage/logs"
          "/srv/pterodactyl/var:/app/var"
        ];
        restart = "unless-stopped";
      };
    };
  };

  systemd.services.pterodactyl-scheduler = {
    description = "Run Pterodactyl artisan scheduler";
    after = [
      "docker.service"
      "docker-compose-pterodactyl.service"
    ];
    requires = [
      "docker.service"
      "docker-compose-pterodactyl.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.docker} exec --user www-data pterodactyl-panel php artisan schedule:run";
    };
  };
  systemd.timers.pterodactyl-scheduler = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/1";
      Unit = "pterodactyl-scheduler.service";
    };
  };

  systemd.services.pterodactyl-wings = {
    description = "Run Pterodactyl Wings";
    after = [
      "docker.service"
      "network-online.target"
      "docker-network-pterodactyl.service"
    ];
    requires = [
      "docker.service"
      "network-online.target"
      "docker-network-pterodactyl.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.shadow ];
    serviceConfig = {
      ExecStart = "${lib.getExe pterodactyl-wings} --config /srv/pterodactyl/wings/config.yml";
      WorkingDirectory = "/srv/pterodactyl/wings";
      Restart = "always";
      RestartSec = 5;
    };
  };

  systemd.services.docker-network-pterodactyl = {
    description = "Ensure Docker network pterodactyl0 exists";
    after = [
      "docker.service"
      "network-online.target"
    ];
    requires = [
      "docker.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.docker pkgs.coreutils pkgs.bash ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      NETWORK_NAME=pterodactyl0
      SUBNET=172.26.0.0/16
      GATEWAY=172.26.0.1

      if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
        echo "Creating $NETWORK_NAME with subnet $SUBNET and bridge $NETWORK_NAME"
        docker network create \
          -d bridge \
          --subnet "$SUBNET" \
          --gateway "$GATEWAY" \
          -o com.docker.network.bridge.name="$NETWORK_NAME" \
          "$NETWORK_NAME"
      fi
    '';
  };

  caddy.proxies = [
    {
      host = "pterodactyl-wings.petr1furious.me";
      target = "http://localhost:8461";
    }
  ];

  networking.firewall.allowedTCPPorts = [ 2461 ];

  systemd.tmpfiles.rules = [
    "d /srv/pterodactyl/wings 0750 root root -"
  ];

  backup.locations.pterodactyl = {
    from = [
      "/srv/pterodactyl"
    ];
  };

  age.secrets.pterodactyl-db-env = {
    file = ../../../secrets/pterodactyl-db-env.age;
  };
  age.secrets.pterodactyl-panel-env = {
    file = ../../../secrets/pterodactyl-panel-env.age;
  };
}
