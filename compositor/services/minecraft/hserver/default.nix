{ config, lib, pkgs, ... }:

{
  virtualisation.compositor.hserver = {
    networks.monitoring.external = true;
    services = {
      mc = {
        container_name = "hserver";
        environment = {
          ENFORCE_SECURE_PROFILE = "FALSE";
          EULA = "TRUE";
          INIT_MEMORY = "4G";
          JVM_OPTS = "-javaagent:authlib-injector.jar=mc-auth.petr1furious.me";
          MAX_MEMORY = "10G";
          TYPE = "PAPER";
          TZ = "Europe/Moscow";
          USE_AIKAR_FLAGS = "TRUE";
          VERSION = "1.21.4";
        };
        image = "itzg/minecraft-server:java21-graalvm";
        labels = [
          "traefik.enable=true"
          "traefik.http.routers.hserver_bluemap.rule=Host(`map.hseminecraft.ru`)"
          "traefik.http.routers.hserver_bluemap.service=hserver_bluemap"
          "traefik.http.services.hserver_bluemap.loadbalancer.server.port=8100"
          "traefik.http.routers.hserver_imageframe.rule=Host(`upload.hseminecraft.ru`)"
          "traefik.http.routers.hserver_imageframe.service=hserver_imageframe"
          "traefik.http.services.hserver_imageframe.loadbalancer.server.port=8517"
        ];
        networks = [ "monitoring" "default" ];
        ports = [ "25565:25565" "24454:24454/udp" ];
        restart = "unless-stopped";
        stdin_open = true;
        tty = true;
        volumes = [ "/srv/minecraft/hserver:/data" ];
      };
    };
  };

  backup.backups.hserver = let docker = lib.getExe pkgs.docker;
  in {
    backupPrepareCommand = ''
      ${docker} exec minigames rcon-cli save-all flush
      ${docker} exec minigames rcon-cli save-off
    '';
    backupCleanupCommand = "${docker} exec minigames rcon-cli save-on";
    schedule = "*:0/30";
    randomizedDelay = "0";
    paths = [ "/srv/minecraft/hserver" ];
  };
}
