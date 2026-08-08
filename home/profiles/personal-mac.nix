{ pkgs, ... }:

{
  imports = [
    ../default.nix
    ../darwin.nix
  ];

  home.packages = with pkgs; [
    autorestic
    rclone
    restic
    zstd
    (writeShellScriptBin "gtar" ''
      exec ${gnutar}/bin/tar "$@"
    '')
  ];

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };
}
