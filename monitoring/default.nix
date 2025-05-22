{
  config,
  lib,
  pkgs,
  ...
}:

let
  grafanaPort = 3000;
  prometheusPort = 9090;
  nodePort = 9100;
  domain = "grafana.petr1furious.me";
in
{
  services.prometheus = {
    enable = true;
    port = prometheusPort;
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        inherit domain;
        http_port = grafanaPort;
      };
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString prometheusPort}";
          uid = "prometheus";
        }
      ];

      dashboards.settings.providers = [
        {
          name = "my dashboards";
          options.path = "/etc/grafana-dashboards";
        }
      ];
    };
  };

  environment.etc."grafana-dashboards/node-exporter-full.json" = {
    source = ./grafana-dashboards/node-exporter-full.json;
    user = "grafana";
    group = "grafana";
  };

  services.prometheus = {
    exporters.node = {
      enable = true;
      listenAddress = "localhost";
      port = nodePort;
    };

    scrapeConfigs = [
      {
        job_name = "node-exporter";
        static_configs = [
          {
            targets = [ "localhost:${toString nodePort}" ];
          }
        ];
      }
    ];
  };

  traefik.proxies = [
    {
      host = domain;
      target = "http://localhost:${toString grafanaPort}";
    }
  ];
}
