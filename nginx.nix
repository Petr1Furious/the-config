{
  config,
  lib,
  pkgs,
  ...
}:

{
  options = with lib; {
    setup.nginxPort = mkOption {
      type = types.int;
      default = 8020;
    };
  };

  config = {
    systemd.services.nginx.serviceConfig.ProtectHome = false;

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;
      defaultListen = [
        {
          addr = "127.0.0.1";
          port = config.setup.nginxPort;
        }
      ];
    };
  };
}
