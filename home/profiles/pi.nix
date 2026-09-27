{ pkgs-unstable, ... }:

{
  imports = [
    ../bme688-exporter.nix
    ../core.nix
    ../linux.nix
    ../pi-display.nix
  ];

  targets.genericLinux = {
    enable = true;
    gpu.enable = false;
  };

  home.packages = [ pkgs-unstable.claude-code ];

  home.sessionVariablesExtra = ''
    export PATH="$PATH:/usr/sbin:/sbin"
  '';

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
