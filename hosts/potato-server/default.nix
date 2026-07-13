{
  modulesPath,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./hardware-configuration.nix
    ./disk-config.nix
    ./relay.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/backup
    ../../modules/nixos/compositor
    ../../modules/nixos/postgres.nix
    ../../modules/nixos/backup-home.nix
    ../../modules/nixos/jitsi.nix
    ../../modules/nixos/nginx.nix
    ../../modules/nixos/immich.nix
    ../../modules/nixos/proxy.nix
    ../../modules/nixos/minecraft
    ../../modules/nixos/monitoring
    ../../modules/nixos/website
    ../../modules/nixos/nixarr.nix
    ../../modules/nixos/nextcloud.nix
    ../../modules/nixos/vaultwarden.nix
    ../../modules/nixos/caddy.nix
    ../../modules/nixos/vscode-server.nix
  ];

  networking.hostName = "potato-server";

  time.timeZone = lib.mkDefault "Europe/Warsaw";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.swraid.mdadmConf = ''
    PROGRAM ${pkgs.coreutils}/bin/true
  '';

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    443
  ];

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  system.stateVersion = "24.11";
}
