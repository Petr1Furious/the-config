{
  config,
  inputs,
  pkgs,
  ...
}:
{
  services.atuin = {
    enable = true;
    package = inputs.nixpkgs-atuin.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin;
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
