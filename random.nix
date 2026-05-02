{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.firewall.allowedTCPPorts = [
    27777
  ];
  networking.firewall.allowedUDPPorts = [
    27777
  ];
}
