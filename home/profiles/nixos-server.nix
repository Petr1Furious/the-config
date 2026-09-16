{ pkgs, ... }:

{
  imports = [
    ../default.nix
    ../linux.nix
  ];

  home.packages = with pkgs; [
    autorestic
    pkgs-unstable.claude-code
    pkgs-unstable.codex
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
