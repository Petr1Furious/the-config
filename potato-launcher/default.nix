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
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQ/qpe93Q2eJdJxsJDA5oKvsfWPFDlzsPaqdWf5Vg/q3yvxwlBRmL5Vlm5qbHlhOka380L+EYtTOspdeiprmPYxYF4B/3TYByc8ehnVON2emUsB6gZ6K4NC/WGx3jPQIiXQ7/OlpG0NafzzTN9RgVL2WyImImNolgThRyCblv+UpL2xd6wRML1C0/eME/j/ZxOObnd9RyMkWQI0OiJLITC0Q0xuLCMSNChgNFPhkS9yTC8HX8+2vgfgKcPYZ9s5wVMHg25MIM2/K6OeAYlFgom06hspiAxRjWlT3tDHzixJc649f8ioiv8FcOJ7uhae7USqDAgFJ5z+PbbodSdZFR/s6ARfufq7hd1lAkVrqz0nOqkM/n26NVW607w8XrrKscfJh255napd1wqnPCL9saTr4wsyNzGintqr+ciX/UdqcQ9R9Fuqh77/m0TZYYW6taRkElaLOVGhNMIbtk5DjLgymwlKDx20VYTrbCZbQGmcP2lzjCnziJGMUYO2vCyqwFPCM2yA+B3oOM1dvjD5+g4jguQSPVWNbV22nGdc9HxvWKGk+ACjQMJzMoOwjQOj9CWSNcsm1T1QScmaK1yQVjqrOS/nS2SqdG+aM14FOtilsiBbe+Rs6h3MvGocE6oi2lmkEY3JsuU6LOXz9Ew35A1fnkB9RwMxiAtwk375C3JBw== petrtsopa03@gmail.com"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDVu8etcldhq3qqOfSOCv10RHaIm6gJe+STWnuT/L461c7ftpfTU3pQsl2N6Tl2oeVKQaDsAgxnGZfqmzbDcZ+gFKRUPZ8FvYT/6sk+RuqgowBEVmtUrr6MOC0ydoMz4aqG0XBkICHvpm652YmgGqp0QN9Rd4QU7yvjKGIwwf5mfYd06HUD8J3zuJqRZFVcA0bfEU/oOJh3MV6Eha412XI3Zx866aYgOntbl0Y2sRUZoSbUhezyVw1rJcJEIQdTcL5HjhCoMcvm/6PaMLdwfsxCqnTt9qTD4V/22nIBooypN1HNnmk2AIDZLzOw2A30rhdfC3bOGYmB7LG13zCe1Av7"
        ];
        uid = 1001;
      };
      groups.potato-launcher.members = [ "nginx" ];
    };
  }

  # (createMcService {
  #   domainName = "mc.petr1furious.me";
  #   publicDir = "${userHome}/public";
  #   certResolver = null;
  # })

  (createMcService {
    domainName = "hseminecraft.ru";
    publicDir = "${userHome}/public-hse";
    certResolver = null;
  })

  (createMcService {
    domainName = "mcitmo.ru";
    publicDir = "${userHome}/public-itmo";
    certResolver = null;
  })

  {
    traefik.proxies = [
      {
        host = "mc.petr1furious.me";
        target = "http://127.0.0.1:8000";
      }
    ];
  }
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
