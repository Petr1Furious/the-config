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
  services.jitsi-videobridge = {
    openFirewall = false;
    config.videobridge.ice.tcp.enabled = false;

    nat = {
      localAddress = "10.99.0.2";
      # Selectel relay address (jitsi.petr1furious.me)
      publicAddress = "82.148.28.127";
    };
  };

  networking.firewall.allowedUDPPorts = [ 10000 ];

  nixpkgs.config.permittedInsecurePackages = [
    "jitsi-meet-1.0.8792"
  ];

  services.nginx.virtualHosts.${hostName} = {
    enableACME = false;
    forceSSL = false;
  };

  caddy.proxies = [
    {
      host = hostName;
      target = "http://127.0.0.1:${toString config.setup.nginxPort}";
    }
  ];

  systemd.services.jitsi-videobridge2 = lib.mkIf config.services.jitsi-meet.prosody.enable {
    after = [ "prosody.service" ];
    requires = [ "prosody.service" ];
  };

  systemd.services.jicofo =
    lib.mkIf (config.services.jitsi-meet.prosody.enable && config.services.jitsi-meet.jicofo.enable)
      {
        after = [ "prosody.service" ];
        requires = [ "prosody.service" ];
      };
}
