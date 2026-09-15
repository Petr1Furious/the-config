{
  config,
  lib,
  pkgs,
  ...
}:

let
  backupDirectory = "/var/lib/postgresql-backup";
  backupFile = "${backupDirectory}/postgres.sql.zst";
  dumpPostgres = pkgs.writeShellScript "backup-postgres-dump" ''
    set -euo pipefail
    umask 077

    ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root "${backupDirectory}"
    tmp="$(${pkgs.coreutils}/bin/mktemp "${backupDirectory}/.postgres.sql.zst.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f -- "$tmp"' EXIT

    /run/wrappers/bin/sudo -u postgres ${config.services.postgresql.package}/bin/pg_dumpall \
      | ${pkgs.zstd}/bin/zstd -T4 > "$tmp"
    ${pkgs.coreutils}/bin/mv -f -- "$tmp" "${backupFile}"
  '';
in
{
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      # TYPE  DATABASE  USER  ADDRESS         METHOD
      host    all       all   172.16.0.0/12   scram-sha-256
    '';
  };

  networking.firewall.interfaces = {
    docker0.allowedTCPPorts = [ 5432 ];
    "br-+".allowedTCPPorts = [ 5432 ];
  };

  backup.locations.postgres = {
    hooks = {
      prevalidate = [ "${dumpPostgres}" ];
      after = [ "${pkgs.coreutils}/bin/rm -f -- ${backupFile}" ];
    };
    from = [ backupFile ];
    options = {
      backup = {
        compression = "off";
      };
    };
  };
}
