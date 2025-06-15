{
  config,
  lib,
  pkgs,
  ...
}:

let
  prometheusExporterPort = "9940";
in
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
        networks = [
          "monitoring"
          "default"
        ];
        ports = [
          "25565:25565"
          "24454:24454/udp"
          "${prometheusExporterPort}:${prometheusExporterPort}"
        ];
        restart = "unless-stopped";
        stdin_open = true;
        tty = true;
        volumes = [ "/srv/minecraft/hserver:/data" ];
      };
    };
  };

  backup.backups.hserver =
    let
      docker = lib.getExe pkgs.docker;
    in
    {
      repository = "rclone:yandex:/minecraft-backups";
      backupPrepareCommand = ''
        ${docker} exec hserver rcon-cli save-all flush
        ${docker} exec hserver rcon-cli save-off
      '';
      backupCleanupCommand = "${docker} exec hserver rcon-cli save-on";
      schedule = "*:00";
      randomizedDelay = "0";
      paths = [ "/srv/minecraft/hserver" ];
      extraBackupArgs = [
        "--exclude=/srv/minecraft/hserver/bluemap"
      ];
    };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "hserver";
      static_configs = [
        {
          targets = [ "localhost:${prometheusExporterPort}" ];
        }
      ];
    }
  ];

  environment.etc."grafana-dashboards/hserver.json" = {
    source = ./grafana-dashboards/hserver.json;
    user = "grafana";
    group = "grafana";
  };
}
