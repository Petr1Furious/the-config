{
  config,
  lib,
  pkgs,
  ...
}:

{
  virtualisation.compositor.overleaf = {
    services = {
      sharelatex = {
        restart = "unless-stopped";
        build = {
          dockerfile = "${./Dockerfile}";
        };
        image = "sharelatex-texlive-full:latest";
        container_name = "sharelatex";
        depends_on = {
          mongo = {
            condition = "service_healthy";
          };
          redis = {
            condition = "service_started";
          };
        };
        stop_grace_period = "60s";
        volumes = [
          "/srv/overleaf:/var/lib/overleaf"
        ];
        environment = {
          OVERLEAF_APP_NAME = "Overleaf Community Edition";
          OVERLEAF_MONGO_URL = "mongodb://mongo/sharelatex";
          OVERLEAF_REDIS_HOST = "redis";
          REDIS_HOST = "redis";
          ENABLED_LINKED_FILE_TYPES = "project_file,project_output_file";
          ENABLE_CONVERSIONS = "true";
          EMAIL_CONFIRMATION_DISABLED = "true";
          OVERLEAF_SITE_URL = "http://overleaf.petr1furious.me";
          OVERLEAF_NAV_TITLE = "Overleaf Community Edition";
        };
        labels = [
          "traefik.enable=true"
          "traefik.http.routers.overleaf.rule=Host(`overleaf.petr1furious.me`)"
        ];
      };

      mongo = {
        restart = "unless-stopped";
        image = "mongo:6.0";
        container_name = "sharelatex-mongo";
        command = ["--replSet" "overleaf"];
        expose = [
          "27017"
        ];
        volumes = [
          "/srv/overleaf/.mongo_data:/data/db"
          "${./mongodb-init-replica-set.js}:/docker-entrypoint-initdb.d/mongodb-init-replica-set.js"
        ];
        environment = {
          MONGO_INITDB_DATABASE = "sharelatex";
        };
        extra_hosts = [
          "mongo:127.0.0.1"
        ];
        healthcheck = {
          test = "echo 'db.stats().ok' | mongosh localhost:27017/test --quiet";
          interval = "10s";
          timeout = "10s";
          retries = 5;
        };
      };

      redis = {
        restart = "unless-stopped";
        image = "redis:6.2";
        container_name = "sharelatex-redis";
        expose = [
          "6379"
        ];
        volumes = [
          "/srv/overleaf/.redis_data:/data"
        ];
      };
    };
  };

  backup.backups.overleaf = {
    paths = [
      "/srv/overleaf"
    ];
  };
}
