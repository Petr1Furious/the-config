{
  config,
  ...
}:

let
  tailnetAddress = "100.75.46.26";
  webPort = 8081;
in
{
  services.pihole-ftl = {
    enable = true;
    queryLogDeleter.enable = true;

    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        description = "Steven Black's unified adlist";
      }
    ];

    settings.dns = {
      listeningMode = "SINGLE";
      interface = "tailscale0";

      upstreams = [
        "9.9.9.9"
        "149.112.112.112"
      ];

      # Only override the tailscale-only proxies (grafana/radarr/sonarr/vaultwarden).
      # Remapping everything, including throughput-sensitive stuff like jellyfin,
      # would significantly decrease performance (userspace wg is notably slow on macos).
      hosts = map (proxy: "${tailnetAddress} ${proxy.host}") (
        builtins.filter (proxy: proxy.tailscaleOnly) config.caddy.proxies
      );
    };
  };

  services.pihole-web = {
    enable = true;
    ports = [ { port = webPort; } ];
  };

  # Upstream's setup script re-POSTs every configured list, so it exits 1 once
  # one is already present, which is every run after the first.
  # But it also masks other exit-1 failures.
  systemd.services.pihole-ftl-setup.serviceConfig.SuccessExitStatus = [ 1 ];

  # Restart FTL once gravity is final to avoid a race between the systemd units.
  systemd.services.pihole-ftl-setup.serviceConfig.ExecStartPost =
    "+${config.systemd.package}/bin/systemctl --no-block try-restart pihole-ftl.service";

  # Refresh blocklists weekly.
  systemd.timers.pihole-ftl-setup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  networking.firewall.interfaces."tailscale0" = {
    allowedUDPPorts = [ 53 ];
    allowedTCPPorts = [
      53
      webPort
    ];
  };

  services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
}
