{ pkgs, ... }:

{
  imports = [
    ../default.nix
    ../linux.nix
  ];

  home.packages = with pkgs; [
    autorestic
    nodejs_24
    rclone
    restic
  ];

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };

  shell.autoAttachTmux = true;
}
