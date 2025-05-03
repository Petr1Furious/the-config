{ config, lib, pkgs, ... }:

{
  virtualisation.compositor.monitoring = {
    networks.monitoring.external = true;
    services = {
      grafana = {
        container_name = "grafana";
        depends_on = [ "prometheus" ];
        image = "grafana/grafana-oss:latest";
        labels = [
          "traefik.enable=true"
          "traefik.http.routers.grafana.rule=Host(`grafana.petr1furious.me`)"
        ];
        restart = "unless-stopped";
        volumes = [
          "${./grafana/grafana.ini}:/etc/grafana/grafana.ini:ro"
          "/srv/monitoring/grafana:/var/lib/grafana"
        ];
      };
      prometheus = {
        command = [ "--config.file=/etc/prometheus/prometheus.yml" ];
        container_name = "prometheus";
        extra_hosts = [ "host.docker.internal:host-gateway" ];
        image = "prom/prometheus:latest";
        networks = [ "monitoring" "default" ];
        restart = "unless-stopped";
        volumes = [
          "${./prometheus/node_rules.yaml}:/etc/prometheus/node_rules.yaml:ro"
          "${./prometheus/prometheus.yml}:/etc/prometheus/prometheus.yml:ro"
          "/srv/monitoring/prometheus:/prometheus"
        ];
      };
    };
  };

  backup.backups.monitoring.paths = [ "/srv/monitoring" ];
}
