{ config, lib, pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      # TYPE  DATABASE  USER  ADDRESS     METHOD
      host    all       all   0.0.0.0/0  scram-sha-256
    '';
  };

  networking.firewall.allowedTCPPorts = [ 5432 ];

  backup.backups.postgres = {
    backupPrepareCommand = ''
      export PATH=${config.services.postgresql.package}/bin:${pkgs.zstd}/bin:$PATH
      /run/wrappers/bin/sudo -u postgres pg_dumpall | zstd -T4 > /tmp/postgres.sql.zst
    '';
    paths = [ "/tmp/postgres.sql.zst" ];
    extraBackupArgs = [ "--compression=off" ];
    backupCleanupCommand = "rm /tmp/postgres.sql.zst";
  };
}
