{
  config,
  lib,
  pkgs,
  secrets,
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
      security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
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

  caddy.proxies = [
    {
      host = domain;
      target = "http://localhost:${toString grafanaPort}";
    }
  ];

  age.secrets.grafana-secret-key = {
    file = secrets + "/grafana-secret-key.age";
    mode = "440";
    owner = "grafana";
    group = "grafana";
  };
}
