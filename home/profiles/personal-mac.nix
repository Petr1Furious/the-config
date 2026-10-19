{
  inputs,
  pkgs,
  pkgs-unstable,
  ...
}:

{
  imports = [
    ../default.nix
    ../darwin.nix
  ];

  home.packages = with pkgs; [
    autorestic
    pkgs-unstable.claude-code
    pkgs-unstable.codex
    mitmproxy
    mpv
    rclone
    restic
    zstd
    (writeShellScriptBin "gtar" ''
      exec ${gnutar}/bin/tar "$@"
    '')
  ];

  # TODO: restore unstable atuin once it builds again
  programs.atuin.package = inputs.nixpkgs-atuin.legacyPackages.${pkgs.stdenv.hostPlatform.system}.atuin;

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };
}
