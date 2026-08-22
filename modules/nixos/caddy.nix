{
  config,
  lib,
  pkgs,
  secrets,
  ...
}:
{
  options = with lib; {
    caddy.proxies = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            host = mkOption { type = types.str; };
            target = mkOption { type = types.str; };
            tailscaleOnly = mkOption {
              type = types.bool;
              default = false;
            };
          };
        }
      );
      default = [ ];
    };
  };

  config =
    let
      virtualHosts = builtins.listToAttrs (
        map (entry: {
          name = entry.host;
          value.extraConfig = ''
            ${lib.optionalString entry.tailscaleOnly ''
              # No public DNS record for this host, so HTTP-01 can't reach it; prove
              # ownership via a DNS-01 TXT record instead.
              tls {
                dns cloudflare {env.CF_API_TOKEN}
              }
              @not-tailnet not remote_ip 100.64.0.0/10
              respond @not-tailnet 403
            ''}
            reverse_proxy ${entry.target}
          '';
        }) config.caddy.proxies
      );
    in
    {
      age.secrets.cloudflare-dns-token.file = secrets + "/cloudflare-dns-token.age";

      services.caddy = {
        enable = true;
        email = "petrtsopa03@gmail.com";
        enableReload = true;
        package = pkgs.caddy.withPlugins {
          plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
          hash = "sha256-PWadA5qr/gR2qDcT8l8u1Xku7LM2HIfWTLOkzezCYy0=";
        };
        globalConfig = ''
          grace_period 30s
        '';
        inherit virtualHosts;
      };

      systemd.services.caddy.serviceConfig.EnvironmentFile = config.age.secrets.cloudflare-dns-token.path;

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
      networking.firewall.allowedUDPPorts = [
        443
      ];
    };
}
