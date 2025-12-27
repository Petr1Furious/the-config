{
  config,
  lib,
  pkgs,
  ...
}:

let
  prometheusExporterPort = "19565";

  docker = lib.getExe pkgs.docker;
  export_docker_host = "export DOCKER_HOST=unix:///run/user/${toString config.users.users.minecraft.uid}/docker.sock";

  make-minecraft-backups = container_names: {
    to = [
      "local-minecraft"
      "yandex-minecraft"
    ];
    hooks = {
      prevalidate = [
        (
          ''
            ${export_docker_host}
          ''
          + (lib.concatStringsSep "\n" (
            map (name: ''
              ${docker} exec ${name} rcon-cli save-all flush
              ${docker} exec ${name} rcon-cli save-off
            '') container_names
          ))
        )
      ];
      after = [
        (
          ''
            ${export_docker_host}
          ''
          + (lib.concatStringsSep "\n" (
            map (name: ''
              ${docker} exec ${name} rcon-cli save-on
            '') container_names
          ))
        )
      ];
    };
  };
  make-launcher-backups =
    launcher-names:
    builtins.listToAttrs (
      map (launcher-name: {
        name = launcher-name;
        value = {
          from = [
            "/home/minecraft/srv/${launcher-name}"
          ];
          options.backup.exclude = [
            "/home/minecraft/srv/${launcher-name}/state/workdir"
          ];
        };
      }) launcher-names
    );
in
{
  users.users.minecraft = {
    isNormalUser = true;
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQ/qpe93Q2eJdJxsJDA5oKvsfWPFDlzsPaqdWf5Vg/q3yvxwlBRmL5Vlm5qbHlhOka380L+EYtTOspdeiprmPYxYF4B/3TYByc8ehnVON2emUsB6gZ6K4NC/WGx3jPQIiXQ7/OlpG0NafzzTN9RgVL2WyImImNolgThRyCblv+UpL2xd6wRML1C0/eME/j/ZxOObnd9RyMkWQI0OiJLITC0Q0xuLCMSNChgNFPhkS9yTC8HX8+2vgfgKcPYZ9s5wVMHg25MIM2/K6OeAYlFgom06hspiAxRjWlT3tDHzixJc649f8ioiv8FcOJ7uhae7USqDAgFJ5z+PbbodSdZFR/s6ARfufq7hd1lAkVrqz0nOqkM/n26NVW607w8XrrKscfJh255napd1wqnPCL9saTr4wsyNzGintqr+ciX/UdqcQ9R9Fuqh77/m0TZYYW6taRkElaLOVGhNMIbtk5DjLgymwlKDx20VYTrbCZbQGmcP2lzjCnziJGMUYO2vCyqwFPCM2yA+B3oOM1dvjD5+g4jguQSPVWNbV22nGdc9HxvWKGk+ACjQMJzMoOwjQOj9CWSNcsm1T1QScmaK1yQVjqrOS/nS2SqdG+aM14FOtilsiBbe+Rs6h3MvGocE6oi2lmkEY3JsuU6LOXz9Ew35A1fnkB9RwMxiAtwk375C3JBw== petrtsopa03@gmail.com"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDVu8etcldhq3qqOfSOCv10RHaIm6gJe+STWnuT/L461c7ftpfTU3pQsl2N6Tl2oeVKQaDsAgxnGZfqmzbDcZ+gFKRUPZ8FvYT/6sk+RuqgowBEVmtUrr6MOC0ydoMz4aqG0XBkICHvpm652YmgGqp0QN9Rd4QU7yvjKGIwwf5mfYd06HUD8J3zuJqRZFVcA0bfEU/oOJh3MV6Eha412XI3Zx866aYgOntbl0Y2sRUZoSbUhezyVw1rJcJEIQdTcL5HjhCoMcvm/6PaMLdwfsxCqnTt9qTD4V/22nIBooypN1HNnmk2AIDZLzOw2A30rhdfC3bOGYmB7LG13zCe1Av7"
    ];
    shell = pkgs.zsh;
    uid = 1002;
  };

  virtualisation.docker.rootless.enable = true;

  backup.locations = {
    modded-hserver = make-minecraft-backups [ "modded_hserver" ] // {
      from = [ "/home/minecraft/modded-hserver" ];
      cron = "30 * * * *";
    };
    minigames =
      make-minecraft-backups [
        "minigames-main"
        "minigames-bedwars"
      ]
      // {
        from = [ "/home/minecraft/minigames" ];
        cron = "0 8 * * *";
      };
  }
  // make-launcher-backups [
    "potato-launcher"
    "hse-launcher"
  ];

  traefik.proxies = [
    {
      host = "mmap.hseminecraft.ru";
      target = "http://localhost:8100";
    }
    {
      host = "metro.hseminecraft.ru";
      target = "http://localhost:3876";
    }
    {
      host = "map.mcitmo.ru";
      target = "http://localhost:8101";
    }
    {
      host = "upload.mcitmo.ru";
      target = "http://localhost:8517";
    }
    {
      host = "mc.petr1furious.me";
      target = "http://127.0.0.1:8001";
    }
    {
      host = "hseminecraft.ru";
      target = "http://127.0.0.1:8002";
    }
    {
      host = "mcitmo.ru";
      target = "http://127.0.0.1:8003";
    }
  ];

  services.prometheus.scrapeConfigs = [
    {
      job_name = "modded-hserver";
      static_configs = [
        {
          targets = [ "localhost:${prometheusExporterPort}" ];
        }
      ];
    }
  ];

  environment.etc."grafana-dashboards/modded-hserver.json" = {
    source = ./grafana-dashboards/modded-hserver.json;
    user = "grafana";
    group = "grafana";
  };
}
