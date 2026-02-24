{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostName = "clipcascade.petr1furious.me";
  dbName = "clipcascade";
  dbUser = "clipcascade";
in
{
  virtualisation.compositor.clipcascade = {
    services = {
      clipcascade = {
        container_name = "clipcascade";
        image = "sathvikrao/clipcascade:latest";
        restart = "always";
        ports = [ "127.0.0.1:8180:8080" ];
        extra_hosts = [ "host.docker.internal:host-gateway" ];
        volumes = [ "/srv/clipcascade:/database" ];
        env_file = config.age.secrets.clipcascade-db-password.path;
        environment = [
          "CC_MAX_MESSAGE_SIZE_IN_MiB=1"
          "CC_P2P_ENABLED=false"
          "CC_SERVER_DB_USERNAME=${dbUser}"
          "CC_SERVER_DB_URL=jdbc:postgresql://host.docker.internal:5432/${dbName}"
          "CC_SERVER_DB_DRIVER=org.postgresql.Driver"
          "CC_SERVER_DB_HIBERNATE_DIALECT=org.hibernate.dialect.PostgreSQLDialect"
          "CC_SIGNUP_ENABLED=false"
        ];
      };
    };
  };

  services.postgresql.ensureDatabases = [ dbName ];
  services.postgresql.ensureUsers = [
    {
      name = dbUser;
      ensureDBOwnership = true;
    }
  ];

  age.secrets.clipcascade-db-password = {
    file = ../../../secrets/clipcascade-db-password.age;
  };

  systemd.services.clipcascade-postgres-password = {
    description = "Set password for ClipCascade postgres role";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.postgresql.package ];
    script = ''
      . ${config.age.secrets.clipcascade-db-password.path}
      /run/wrappers/bin/sudo -u postgres psql -v ON_ERROR_STOP=1 --set=db_password="$CC_SERVER_DB_PASSWORD" <<'SQL'
      ALTER ROLE ${dbUser} WITH PASSWORD :'db_password';
      SQL
    '';
    serviceConfig = {
      Type = "oneshot";
    };
  };

  systemd.services.docker-compose-clipcascade = {
    after = [ "clipcascade-postgres-password.service" ];
    requires = [ "clipcascade-postgres-password.service" ];
  };

  caddy.proxies = [
    {
      host = hostName;
      target = "http://127.0.0.1:8180";
    }
  ];

  backup.locations.clipcascade = {
    from = [ "/srv/clipcascade" ];
  };
}
