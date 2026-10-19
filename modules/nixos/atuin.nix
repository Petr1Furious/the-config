{ config, ... }:
{
  services.atuin = {
    enable = true;
    host = "127.0.0.1";
    port = 8889;
    openRegistration = true;
  };

  caddy.proxies = [
    {
      host = "atuin.petr1furious.me";
      target = "http://127.0.0.1:${toString config.services.atuin.port}";
      tailscaleOnly = true;
    }
  ];
}
