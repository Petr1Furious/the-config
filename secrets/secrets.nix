let
  admin = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQ/qpe93Q2eJdJxsJDA5oKvsfWPFDlzsPaqdWf5Vg/q3yvxwlBRmL5Vlm5qbHlhOka380L+EYtTOspdeiprmPYxYF4B/3TYByc8ehnVON2emUsB6gZ6K4NC/WGx3jPQIiXQ7/OlpG0NafzzTN9RgVL2WyImImNolgThRyCblv+UpL2xd6wRML1C0/eME/j/ZxOObnd9RyMkWQI0OiJLITC0Q0xuLCMSNChgNFPhkS9yTC8HX8+2vgfgKcPYZ9s5wVMHg25MIM2/K6OeAYlFgom06hspiAxRjWlT3tDHzixJc649f8ioiv8FcOJ7uhae7USqDAgFJ5z+PbbodSdZFR/s6ARfufq7hd1lAkVrqz0nOqkM/n26NVW607w8XrrKscfJh255napd1wqnPCL9saTr4wsyNzGintqr+ciX/UdqcQ9R9Fuqh77/m0TZYYW6taRkElaLOVGhNMIbtk5DjLgymwlKDx20VYTrbCZbQGmcP2lzjCnziJGMUYO2vCyqwFPCM2yA+B3oOM1dvjD5+g4jguQSPVWNbV22nGdc9HxvWKGk+ACjQMJzMoOwjQOj9CWSNcsm1T1QScmaK1yQVjqrOS/nS2SqdG+aM14FOtilsiBbe+Rs6h3MvGocE6oi2lmkEY3JsuU6LOXz9Ew35A1fnkB9RwMxiAtwk375C3JBw== petrtsopa03@gmail.com";
  potato_server = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFu0hmSgRB/X46yemDNfwldqQKWU1fkorCI94qokIpUW";
  vm_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH6tQWk4OUIreAOhMy/UH7CmtfHFcLGZNyPOhjVkwd6i";

  publicKeys = [
    admin
    potato_server
    vm_key
  ];

  files = [
    "restic-key.age"
    "rclone-config.age"
    "vaultwarden-admin-token.age"
    "tgauth-key.age"
    "tgauth-env.age"
    "traefik-env.age"
    "htpasswd.age"
    "sing-box-proxy-blocked.age"
    "sing-box-proxy-all-except-ru.age"
    "sing-box-proxy-all.age"
    "sing-box-http-proxy.age"
    "nextcloud-admin-password.age"
    "xray-proxy.age"
  ];
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value.publicKeys = publicKeys;
  }) files
)
