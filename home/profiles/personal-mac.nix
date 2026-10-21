{
  config,
  inputs,
  pkgs,
  pkgs-unstable,
  ...
}:

{
  imports = [
    inputs.agenix.homeManagerModules.default
    ../default.nix
    ../claude.nix
    ../darwin.nix
  ];

  home.packages = with pkgs; [
    autorestic
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

  age.secrets = {
    claude-grafana-mcp-token.file = ../../secrets/claude-grafana-mcp-token.age;
  };

  claude.grafanaTokenFile = config.age.secrets.claude-grafana-mcp-token.path;

  programs.git.settings.user = {
    name = "Petr Tsopa";
    email = "petrtsopa03@gmail.com";
  };
}
