{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./minecraft-user.nix
  ];

  networking.firewall = {
    allowedTCPPortRanges = [
      {
        from = 25565;
        to = 25574;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 24454;
        to = 24463;
      }
    ];
  };
}
