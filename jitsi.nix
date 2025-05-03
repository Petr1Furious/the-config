{
  config,
  lib,
  pkgs,
  ...
}:

let
  hostName = "jitsi.petr1furious.me";
in
{
  services.jitsi-meet = {
    enable = true;
    inherit hostName;
    prosody.lockdown = true;
    config = {
      prejoinPageEnabled = true;
    };
    interfaceConfig = {
      SHOW_JITSI_WATERMARK = false;
      SHOW_WATERMARK_FOR_GUESTS = false;
    };
  };
  services.jitsi-videobridge.openFirewall = true;

  nixpkgs.config.permittedInsecurePackages = [
    "jitsi-meet-1.0.8043"
  ];

  services.nginx.virtualHosts.${hostName} = {
    enableACME = false;
    forceSSL = false;
  };

  traefik.proxies = [
    {
      host = hostName;
      target = "http://127.0.0.1:${toString config.setup.nginxPort}";
    }
  ];
}
