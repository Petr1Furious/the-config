{ config, ... }:

let
  socksPort = 10808;
  httpPort = 10809;
  namespaceAddress = config.vpnNamespaces.wg.namespaceAddress;
in
{
  services.sing-box = {
    enable = true;
    settings = {
      log.level = "warn";
      inbounds = [
        {
          type = "socks";
          tag = "socks-in";
          listen = namespaceAddress;
          listen_port = socksPort;
        }
        {
          type = "http";
          tag = "http-in";
          listen = namespaceAddress;
          listen_port = httpPort;
        }
      ];
      outbounds = [
        {
          type = "direct";
          tag = "direct";
        }
      ];
    };
  };

  systemd.services.sing-box.vpnConfinement = {
    enable = true;
    vpnNamespace = "wg";
  };

  vpnNamespaces.wg.portMappings = [
    {
      from = socksPort;
      to = socksPort;
    }
    {
      from = httpPort;
      to = httpPort;
    }
  ];

  # portMappings only DNAT traffic arriving from outside; the host's own
  # connections to loopback need a forward.
  services.nginx.streamConfig = ''
    server {
      listen 127.0.0.1:${toString socksPort};
      proxy_pass ${namespaceAddress}:${toString socksPort};
    }
    server {
      listen 127.0.0.1:${toString httpPort};
      proxy_pass ${namespaceAddress}:${toString httpPort};
    }
  '';
}
