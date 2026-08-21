{
  config,
  inputs,
  ...
}:

let
  qbitPeerPort = 51413;
  singBoxSocksPort = 10808;
  qbitWebuiPort = 5252;
  qbitInternalPort = config.nixarr.qbittorrent.qui.internalPort;

  seerrPort = config.nixarr.seerr.port;
  bazarrPort = config.nixarr.bazarr.port;
  prowlarrPort = config.nixarr.prowlarr.port;
in
{
  imports = [ inputs.nixarr.nixosModules.default ];

  services.flaresolverr.enable = true;

  nixarr = {
    enable = true;

    mediaDir = "/srv/media";
    stateDir = "/srv/media/.state/nixarr";

    jellyfin.enable = true;
    radarr.enable = true;
    sonarr.enable = true;
    prowlarr.enable = true;
    bazarr.enable = true;
    seerr.enable = true;

    # settings-sync only ships a canned Transmission block, so qBittorrent has
    # to go through the generic list. Categories must match the qBittorrent
    # category save paths or imports stop being hardlinked.
    sonarr.settings-sync.downloadClients = [
      {
        name = "qBittorrent";
        implementation = "QBittorrent";
        enable = true;
        fields = {
          host = "localhost";
          port = qbitInternalPort;
          useSsl = false;
          tvCategory = "sonarr";
        };
      }
    ];

    radarr.settings-sync.downloadClients = [
      {
        name = "qBittorrent";
        implementation = "QBittorrent";
        enable = true;
        fields = {
          host = "localhost";
          port = qbitInternalPort;
          useSsl = false;
          movieCategory = "radarr";
        };
      }
    ];

    bazarr.settings-sync = {
      sonarr.enable = true;
      radarr.enable = true;
    };

    # Indexers stay runtime-only deliberately, backups already cover them.

    qbittorrent = {
      enable = true;
      peerPort = qbitPeerPort;
      webuiPort = qbitWebuiPort;
      exporter.listenAddr = "127.0.0.1";

      extraConfig = {
        BitTorrent = {
          "Session\\GlobalMaxRatio" = 1.0;
          "Session\\GlobalMaxInactiveSeedingMinutes" = 1440;
          "Session\\ShareLimitAction" = "RemoveWithContent";

          "Session\\ProxyPeerConnections" = true;
          "Session\\AnonymousModeEnabled" = true;
          "Session\\DHTEnabled" = false;
          "Session\\LSDEnabled" = false;
          "Session\\PeXEnabled" = true;
        };

        # Without a [Meta] section qBittorrent treats the generated file as
        # pre-migration and reruns migrateProxySettings on every start, which
        # resets Proxy\HostnameLookupEnabled to false.
        Meta."MigrationVersion" = 8;

        Network = {
          "Proxy\\Type" = "SOCKS5";
          "Proxy\\IP" = "127.0.0.1";
          "Proxy\\Port" = singBoxSocksPort;
          "Proxy\\AuthEnabled" = false;
          "Proxy\\HostnameLookupEnabled" = true;
          "Proxy\\Profiles\\BitTorrent" = true;
          "Proxy\\Profiles\\RSS" = true;
          "Proxy\\Profiles\\Misc" = true;
        };
      };
    };

    recyclarr = {
      enable = true;
      # The 1080p and 2160p profiles share one instance block: recyclarr
      # silently syncs nothing ("Split instances") when two instances
      # point at the same base_url.
      configuration = {
        sonarr.series = {
          base_url = "http://localhost:8989";
          api_key = "!env_var SONARR_API_KEY";
          quality_definition.type = "series";
          quality_profiles = [
            {
              trash_id = "72dae194fc92bf828f32cde7744e51a1"; # WEB-1080p
              reset_unmatched_scores.enabled = true;
            }
            {
              trash_id = "d1498e7d189fbe6c7110ceaabb7473e6"; # WEB-2160p
              reset_unmatched_scores.enabled = true;
            }
          ];
          custom_format_groups.add = [
            { trash_id = "158188097a58d7687dee647e04af0da3"; } # Golden Rule HD
            { trash_id = "e3f37512790f00d0e89e54fe5e790d1c"; } # Golden Rule UHD
            { trash_id = "74aff4168620ed49dcc67e92b2c2a5b4"; } # Language Profiles
            { trash_id = "85fae4a2294965b75710ef2989c850eb"; } # Streaming HD/UHD boost
            { trash_id = "59c3af66780d08332fdc64e68297098f"; } # Unwanted Formats
            # Profile-5 DV has no HDR10 compatibility.
            { trash_id = "d776a1ea912a117d66d83b880ff2055d"; } # DV (w/o HDR fallback)
          ];
        };
        radarr.movies = {
          base_url = "http://localhost:7878";
          api_key = "!env_var RADARR_API_KEY";
          quality_definition.type = "movie";
          quality_profiles = [
            {
              trash_id = "d1d67249d3890e49bc12e275d989a7e9"; # HD Bluray + WEB
              reset_unmatched_scores.enabled = true;
            }
            {
              trash_id = "64fb5f9858489bdac2af690e27c8f42f"; # UHD Bluray + WEB
              reset_unmatched_scores.enabled = true;
            }
          ];
          custom_format_groups.add = [
            { trash_id = "f8bf8eab4617f12dfdbd16303d8da245"; } # Golden Rule HD
            { trash_id = "ff204bbcecdd487d1cefcefdbf0c278d"; } # Golden Rule UHD
            { trash_id = "a3ac6af01d78e4f21fcb75f601ac96df"; } # Unwanted Formats
            { trash_id = "7fc2751eef7e6bdc70b74136e5e35c76"; } # DV (w/o HDR fallback)
          ];
        };
      };
    };

    exporters.enable = true;

    # nixarr opens every non-VPN-confined exporter port in the firewall, so
    # bind them to loopback to leave nothing behind those holes.
    sonarr.exporter.listenAddr = "127.0.0.1";
    radarr.exporter.listenAddr = "127.0.0.1";
    prowlarr.exporter.listenAddr = "127.0.0.1";
  };

  systemd.services.prowlarr = {
    after = [ "sing-box.service" ];
    wants = [ "sing-box.service" ];
  };

  systemd.services.qbittorrent = {
    after = [ "sing-box.service" ];
    wants = [ "sing-box.service" ];

    # nixarr sets this for transmission but not qbittorrent, which then leaves
    # finished files group-read-only. fs.protected_hardlinks then denies
    # Sonarr/Radarr the link(), and they silently copy instead.
    serviceConfig.UMask = "0002";
  };

  backup.locations.nixarr = {
    from = [
      "/srv/media/.state/nixarr"
    ];
    options.backup.exclude = [
      "/srv/media/.state/nixarr/jellyfin/cache"
    ];
  };

  caddy.proxies = [
    {
      host = "jellyfin.petr1furious.me";
      target = "http://127.0.0.1:8096";
    }
    {
      host = "seerr.petr1furious.me";
      target = "http://127.0.0.1:${toString seerrPort}";
    }
    {
      host = "radarr.petr1furious.me";
      target = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
      tailscaleOnly = true;
    }
    {
      host = "sonarr.petr1furious.me";
      target = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
      tailscaleOnly = true;
    }
    {
      host = "prowlarr.petr1furious.me";
      target = "http://127.0.0.1:${toString prowlarrPort}";
      tailscaleOnly = true;
    }
    {
      host = "bazarr.petr1furious.me";
      target = "http://127.0.0.1:${toString bazarrPort}";
      tailscaleOnly = true;
    }
    {
      host = "qbit.petr1furious.me";
      target = "http://127.0.0.1:${toString qbitWebuiPort}";
      tailscaleOnly = true;
    }
  ];
}
