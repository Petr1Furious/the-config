{
  config,
  lib,
  pkgs,
  ...
}:

{
  virtualisation.compositor.minigames = {
    networks.monitoring.external = true;
    services = {
      mc = {
        container_name = "minigames";
        environment = {
          ENFORCE_SECURE_PROFILE = "FALSE";
          EULA = "TRUE";
          INIT_MEMORY = "2G";
          JVM_OPTS = "-javaagent:authlib-injector.jar=mc-auth.petr1furious.me";
          MAX_MEMORY = "6G";
          TYPE = "PAPER";
          TZ = "Europe/Moscow";
          USE_AIKAR_FLAGS = "TRUE";
          VERSION = "1.21.1";
        };
        image = "itzg/minecraft-server:java21-graalvm";
        ports = [
          "25567:25565"
        ];
        restart = "unless-stopped";
        stdin_open = true;
        tty = true;
        volumes = [ "/srv/minecraft/minigames:/data" ];
      };
    };
  };

  backup.backups.minigames =
    let
      docker = lib.getExe pkgs.docker;
    in
    {
      repository = "rclone:yandex:/minecraft-backups";
      backupPrepareCommand = ''
        ${docker} exec minigames rcon-cli save-all flush
        ${docker} exec minigames rcon-cli save-off
      '';
      backupCleanupCommand = "${docker} exec minigames rcon-cli save-on";
      schedule = "00/8:00:00";
      randomizedDelay = "1h";
      paths = [ "/srv/minecraft/minigames" ];
    };
}
