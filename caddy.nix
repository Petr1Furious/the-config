{
  config,
  lib,
  pkgs,
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
            reverse_proxy ${entry.target}
          '';
        }) config.caddy.proxies
      );
    in
    {
      services.caddy = {
        enable = true;
        email = "petrtsopa03@gmail.com";
        enableReload = true;
        package = pkgs.caddy.withPlugins {
          plugins = [ "github.com/lucaslorentz/caddy-docker-proxy/v2@v2.10.0" ];
          hash = "sha256-uv0KqU3CNosm87ugDytEEujOs685ZexNQu5Y2uFvxps=";
        };
        globalConfig = ''
          grace_period 30s
        '';
        inherit virtualHosts;
      };

      users.users.caddy.extraGroups = [ "docker" ];

      systemd.services.caddy = {
        after = [ "docker.service" ];
        requires = [ "docker.service" ];
        serviceConfig.ExecStart = lib.mkForce [
          ""
          "${lib.getExe config.services.caddy.package} docker-proxy --caddyfile-path ${config.services.caddy.configFile}"
        ];
      };

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    };
}
