{
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../common/nix.nix
    ./tailscale.nix
    inputs.agenix.nixosModules.default
  ];

  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  services.fail2ban.enable = true;

  security.sudo.wheelNeedsPassword = false;

  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
  };

  users.users.petrtsopa = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYb7/Z36wmmKSdZ9RCvMtyb2LB5RATwNJFwftJ56VFz personal-macbook-2026-08"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwFnjh88nmFf8hUcE20aYhkul2RN6gghrZUVJ1hxwoa second-macbook-2026-08"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGBPXCsXxvBzf7idsv8VhUwKc9+GM5vsGJ78HhjGxLyX phone-2026-08"
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    ghostty.terminfo
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.nix-ld.enable = true;
}
