{ ... }:

{
  imports = [
    ../bme688-exporter.nix
    ../claude.nix
    ../core.nix
    ../ld2410-stream.nix
    ../linux.nix
    ../pi-display.nix
  ];

  targets.genericLinux = {
    enable = true;
    gpu.enable = false;
  };

  home.sessionVariablesExtra = ''
    export PATH="$PATH:/usr/sbin:/sbin"
  '';

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };

  claude.github.enable = false;
  claude.playwright.enable = false;

  shell.autoAttachTmux = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
