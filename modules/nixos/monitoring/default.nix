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
  alertmanagerPort = 9093;
  blackboxPort = 9115;
  domain = "grafana.petr1furious.me";
  alertmanagerDomain = "alertmanager.petr1furious.me";

  telegramChatId = 702629742;

  nginxUrl = "http://127.0.0.1:${toString config.setup.nginxPort}";

  httpProbeTargets = [
    {
      service = "tgauth";
      url = "http://127.0.0.1:8130/";
    }
    {
      service = "jellyfin";
      url = "http://127.0.0.1:8096/health";
    }
    {
      service = "seerr";
      url = "http://127.0.0.1:5055/api/v1/status";
    }
    {
      service = "sonarr";
      url = "http://127.0.0.1:8989/ping";
    }
    {
      service = "radarr";
      url = "http://127.0.0.1:7878/ping";
    }
    {
      service = "prowlarr";
      url = "http://127.0.0.1:9696/ping";
    }
    {
      service = "bazarr";
      url = "http://127.0.0.1:6767/api/system/ping";
    }
    {
      service = "qbittorrent";
      url = "http://127.0.0.1:${toString config.nixarr.qbittorrent.qui.internalPort}/api/v2/app/version";
    }
    {
      service = "qui";
      url = "http://127.0.0.1:5252/health";
    }
    {
      service = "vaultwarden";
      url = "http://127.0.0.1:8222/alive";
    }
    {
      service = "immich";
      url = "http://localhost:${toString config.services.immich.port}/api/server/ping";
    }
    {
      service = "nextcloud";
      url = "${nginxUrl}/status.php";
      host = "nextcloud.petr1furious.me";
      failIfBodyMatches = [ ''"maintenance":\s*true'' ];
      failIfBodyNotMatches = [ ''"productname":\s*"Nextcloud"'' ];
    }
    {
      service = "jitsi";
      url = "${nginxUrl}/http-bind";
      host = "jitsi.petr1furious.me";
      failIfBodyNotMatches = [ "Prosody" ];
    }
    {
      service = "jitsi-videobridge";
      url = "http://127.0.0.1:8080/about/health";
    }
    {
      service = "jicofo";
      url = "http://127.0.0.1:8888/about/version";
    }
    {
      service = "grafana";
      url = "http://127.0.0.1:${toString grafanaPort}/api/health";
    }
    {
      service = "hseminecraft-site";
      url = "http://127.0.0.1:8001/";
    }
    {
      service = "hseminecraft-map";
      url = "http://127.0.0.1:8100/";
    }
    {
      service = "hseminecraft-mmap";
      url = "http://127.0.0.1:8101/";
    }
  ];

  probeModule = t: "http_${t.service}";
in
{
  options.monitoring.textfileDirectory = lib.mkOption {
    type = lib.types.path;
    default = "/var/lib/prometheus-node-exporter-text-files";
    description = "Directory node_exporter's textfile collector reads ad-hoc metrics from.";
  };

  config = {
    systemd.tmpfiles.rules = [
      "d ${config.monitoring.textfileDirectory} 0755 root root -"
    ];

    services.prometheus = {
      enable = true;
      port = prometheusPort;

      exporters.node = {
        enable = true;
        listenAddress = "localhost";
        port = nodePort;
        # nixarr's own monitoring integration already enables "systemd" (plus
        # tcpstat/network_route) on this exporter
        enabledCollectors = [ "textfile" ];
        extraFlags = [ "--collector.textfile.directory=${config.monitoring.textfileDirectory}" ];
      };

      exporters.blackbox = {
        enable = true;
        listenAddress = "localhost";
        port = blackboxPort;
        configFile = pkgs.writeText "blackbox.yml" (
          builtins.toJSON {
            modules = lib.listToAttrs (
              map (t: {
                name = probeModule t;
                value = {
                  prober = "http";
                  timeout = "5s";
                  http = {
                    method = "GET";
                  }
                  // lib.optionalAttrs (t ? host) { headers.Host = t.host; }
                  // lib.optionalAttrs (t ? failIfBodyMatches) {
                    fail_if_body_matches_regexp = t.failIfBodyMatches;
                  }
                  // lib.optionalAttrs (t ? failIfBodyNotMatches) {
                    fail_if_body_not_matches_regexp = t.failIfBodyNotMatches;
                  };
                };
              }) httpProbeTargets
            );
          }
        );
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
        {
          job_name = "blackbox-http";
          metrics_path = "/probe";
          static_configs = map (t: {
            targets = [ t.url ];
            labels = {
              inherit (t) service;
              __param_module = probeModule t;
            };
          }) httpProbeTargets;
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            {
              target_label = "__address__";
              replacement = "localhost:${toString blackboxPort}";
            }
          ];
        }
        {
          job_name = "bme688";
          scrape_interval = "30s";
          static_configs = [ { targets = [ "100.67.147.81:9688" ]; } ];
        }
      ]
      ++
        map
          (e: {
            job_name = e.name;
            scrape_interval = "60s";
            static_configs = [ { targets = [ "127.0.0.1:${toString e.port}" ]; } ];
          })
          (
            lib.optionals config.nixarr.exporters.enable [
              {
                name = "sonarr";
                port = config.nixarr.sonarr.exporter.port;
              }
              {
                name = "radarr";
                port = config.nixarr.radarr.exporter.port;
              }
              {
                name = "prowlarr";
                port = config.nixarr.prowlarr.exporter.port;
              }
              {
                name = "qbittorrent";
                port = config.nixarr.qbittorrent.exporter.port;
              }
            ]
          );

      ruleFiles = [
        (pkgs.writeText "systemd-and-target-alerts.rules.yml" ''
          groups:
            - name: systemd
              rules:
                - alert: SystemdUnitFailed
                  expr: node_systemd_unit_state{state="failed"} == 1
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "{{ $labels.name }} failed on {{ $labels.instance }}"
                    description: "systemd unit {{ $labels.name }} has been in the failed state for more than 5 minutes."
            - name: scrape-targets
              rules:
                - alert: PrometheusTargetDown
                  expr: up == 0
                  for: 10m
                  labels:
                    severity: warning
                  annotations:
                    summary: "Scrape target {{ $labels.job }} ({{ $labels.instance }}) is down"
                    description: "Prometheus has not been able to scrape {{ $labels.job }}/{{ $labels.instance }} for 10 minutes."
            - name: blackbox
              rules:
                - alert: HttpProbeFailed
                  expr: probe_success == 0
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "{{ $labels.service }} ({{ $labels.instance }}) is not responding over HTTP"
                    description: "blackbox_exporter has not gotten a successful HTTP response from {{ $labels.service }} for 5 minutes."
            - name: bme688
              rules:
                - alert: Bme688SamplesStale
                  expr: time() - bme688_last_sample_timestamp_seconds > 300
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: "BME688 on {{ $labels.instance }} has stopped producing samples"
                    description: "The exporter still answers, but its last sample is more than 5 minutes old, so the sensor loop is stuck."
        '')
      ];

      alertmanagers = [
        { static_configs = [ { targets = [ "localhost:${toString alertmanagerPort}" ]; } ]; }
      ];

      alertmanager = {
        enable = true;
        listenAddress = "localhost";
        port = alertmanagerPort;
        configuration = {
          route = {
            receiver = "telegram";
            group_by = [ "alertname" ];
            group_wait = "30s";
            group_interval = "5m";
            repeat_interval = "4h";
          };
          receivers = [
            {
              name = "telegram";
              telegram_configs = [
                {
                  bot_token_file = "/run/credentials/alertmanager.service/telegram-bot-token";
                  chat_id = telegramChatId;
                  parse_mode = "HTML";
                  send_resolved = true;
                }
              ];
            }
          ];
        };
      };
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

    environment.etc."grafana-dashboards/air-quality.json" = {
      source = ./grafana-dashboards/air-quality.json;
      user = "grafana";
      group = "grafana";
    };

    environment.etc."grafana-dashboards/services-overview.json" = {
      source = ./grafana-dashboards/services-overview.json;
      user = "grafana";
      group = "grafana";
    };

    systemd.services.alertmanager.serviceConfig.LoadCredential =
      "telegram-bot-token:${config.age.secrets.telegram-bot-token.path}";

    caddy.proxies = [
      {
        host = domain;
        target = "http://localhost:${toString grafanaPort}";
        tailscaleOnly = true;
      }
      {
        host = alertmanagerDomain;
        target = "http://localhost:${toString alertmanagerPort}";
        tailscaleOnly = true;
      }
    ];

    age.secrets.grafana-secret-key = {
      file = secrets + "/grafana-secret-key.age";
      mode = "440";
      owner = "grafana";
      group = "grafana";
    };

    age.secrets.telegram-bot-token = {
      file = secrets + "/telegram-bot-token.age";
    };
  };
}
