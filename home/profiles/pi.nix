{ pkgs-unstable, ... }:

{
  imports = [
    ../core.nix
    ../linux.nix
  ];

  targets.genericLinux = {
    enable = true;
    gpu.enable = false;
  };

  home.packages = [ pkgs-unstable.claude-code ];

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };

  shell.autoAttachTmux = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
