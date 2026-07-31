{ pkgs, ... }:

{
  imports = [
    ../default.nix
    ../linux.nix
  ];

  home.packages = with pkgs; [
    autorestic
    gcc
    pciutils
    rclone
    restic
  ];

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };

  shell.autoAttachTmux = true;
}
