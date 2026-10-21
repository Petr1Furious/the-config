{ pkgs, pkgs-unstable, ... }:

{
  imports = [
    ../default.nix
    ../claude.nix
    ../linux.nix
  ];

  home.packages = with pkgs; [
    autorestic
    pkgs-unstable.codex
    gcc
    gh
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
