{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./restic.nix
    ./compositor
    ./minecraft.nix
    ./potato-launcher
    ./postgres.nix
    ./backup-home.nix
    ./jitsi.nix
    ./nginx.nix
    ./immich.nix
    ./minecraft-user.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = "potato-server";

  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "en_US.UTF-8";

  users.users.petrtsopa = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQ/qpe93Q2eJdJxsJDA5oKvsfWPFDlzsPaqdWf5Vg/q3yvxwlBRmL5Vlm5qbHlhOka380L+EYtTOspdeiprmPYxYF4B/3TYByc8ehnVON2emUsB6gZ6K4NC/WGx3jPQIiXQ7/OlpG0NafzzTN9RgVL2WyImImNolgThRyCblv+UpL2xd6wRML1C0/eME/j/ZxOObnd9RyMkWQI0OiJLITC0Q0xuLCMSNChgNFPhkS9yTC8HX8+2vgfgKcPYZ9s5wVMHg25MIM2/K6OeAYlFgom06hspiAxRjWlT3tDHzixJc649f8ioiv8FcOJ7uhae7USqDAgFJ5z+PbbodSdZFR/s6ARfufq7hd1lAkVrqz0nOqkM/n26NVW607w8XrrKscfJh255napd1wqnPCL9saTr4wsyNzGintqr+ciX/UdqcQ9R9Fuqh77/m0TZYYW6taRkElaLOVGhNMIbtk5DjLgymwlKDx20VYTrbCZbQGmcP2lzjCnziJGMUYO2vCyqwFPCM2yA+B3oOM1dvjD5+g4jguQSPVWNbV22nGdc9HxvWKGk+ACjQMJzMoOwjQOj9CWSNcsm1T1QScmaK1yQVjqrOS/nS2SqdG+aM14FOtilsiBbe+Rs6h3MvGocE6oi2lmkEY3JsuU6LOXz9Ew35A1fnkB9RwMxiAtwk375C3JBw== petrtsopa03@gmail.com"
    ];
    shell = pkgs.zsh;
  };

  security.sudo.wheelNeedsPassword = false;

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    vim
    wget
    htop
    git
    nixfmt-rfc-style
    tealdeer
    peco
  ];

  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
  };

  backup.enable = false;

  services.openssh.enable = true;

  services.vscode-server.enable = true;

  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [ 443 ];

  system.stateVersion = "24.11"; # Do not touch this value unless you know what you are doing.

  virtualisation.vmVariant = {
    security.sudo.wheelNeedsPassword = false;
    virtualisation = {
      graphics = false;
      memorySize = 4096;
      cores = 16;
      diskSize = 10 * 1024;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
    };
  };
}
