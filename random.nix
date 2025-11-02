{
  config,
  lib,
  pkgs,
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    27015
  ];
}
