{
  config,
  lib,
  pkgs,
  ...
}:

let
  userName = "potato-launcher";
  groupName = "potato-launcher";

  userHome = config.users.users.${userName}.home;

  createMcService =
    {
      domainName,
      publicDir,
      certResolver,
    }:
    {
      services.nginx.virtualHosts.${domainName} = {
        locations."= /" = {
          root = ./.;
          tryFiles = "/${domainName}.html =404";
        };
        locations."/" = {
          root = publicDir + "/launcher";
        };
        locations."/launcher" = {
          root = publicDir;
        };
        locations."/data" = {
          root = publicDir;
          extraConfig = "autoindex on;";
        };
      };

      traefik.proxies = [
        {
          host = domainName;
          target = "http://127.0.0.1:${toString config.setup.nginxPort}";
          inherit certResolver;
        }
      ];

      systemd.tmpfiles.rules = [ "d ${publicDir} 0750 ${userName} ${groupName} - -" ];
    };
in
lib.mkMerge [
  {
    users = {
      users.potato-launcher = {
        isNormalUser = true;
        group = "potato-launcher";
        homeMode = "750";
        shell = pkgs.bash;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKKBNJwG0teuMiHeOJ0PooR2Ua6ApLCpZU3ZrIui1hsv potato-launcher@petrtsopa"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDVu8etcldhq3qqOfSOCv10RHaIm6gJe+STWnuT/L461c7ftpfTU3pQsl2N6Tl2oeVKQaDsAgxnGZfqmzbDcZ+gFKRUPZ8FvYT/6sk+RuqgowBEVmtUrr6MOC0ydoMz4aqG0XBkICHvpm652YmgGqp0QN9Rd4QU7yvjKGIwwf5mfYd06HUD8J3zuJqRZFVcA0bfEU/oOJh3MV6Eha412XI3Zx866aYgOntbl0Y2sRUZoSbUhezyVw1rJcJEIQdTcL5HjhCoMcvm/6PaMLdwfsxCqnTt9qTD4V/22nIBooypN1HNnmk2AIDZLzOw2A30rhdfC3bOGYmB7LG13zCe1Av7"
        ];
        uid = 1001;
      };
      groups.potato-launcher.members = [ "nginx" ];
    };
  }

  (createMcService {
    domainName = "mc.petr1furious.me";
    publicDir = "${userHome}/public";
    certResolver = null;
  })

  (createMcService {
    domainName = "hseminecraft.ru";
    publicDir = "${userHome}/public-hse";
    certResolver = null;
  })

  (createMcService {
    domainName = "mipt.petr1furious.me";
    publicDir = "${userHome}/public-mipt";
    certResolver = null;
  })
]
// {
  backup.locations.potato-launcher = {
    from = [
      "/home/potato-launcher"
    ];
    options = {
      backup = {
        exclude = [
          "/home/potato-launcher/.cache"
        ];
      };
    };
  };
}
