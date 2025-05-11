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

  backup.backups.modded-hserver =
    let
      docker = lib.getExe pkgs.docker;
      export_docker_host = "export DOCKER_HOST=unix:///run/user/${toString config.users.users.minecraft.uid}/docker.sock";
    in
    {
      backupPrepareCommand = ''
        ${export_docker_host}
        ${docker} exec modded_hserver rcon-cli save-all flush
        ${docker} exec modded_hserver rcon-cli save-off
      '';
      backupCleanupCommand = ''
        ${export_docker_host}
        ${docker} exec modded_hserver rcon-cli save-on
      '';
      schedule = "*:0/30";
      randomizedDelay = "0";
      paths = [ "/home/minecraft/modded-hserver" ];
    };

  traefik.proxies = [
    {
      host = "mmap.hseminecraft.ru";
      target = "http://localhost:8100";
    }
  ];
}
