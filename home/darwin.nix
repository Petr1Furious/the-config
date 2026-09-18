{
  lib,
  pkgs,
  inputs,
  ...
}:

lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  home.packages = with pkgs; [
    (writeShellScriptBin "timeout" ''
      exec ${coreutils}/bin/timeout "$@"
    '')
    ghostscript
    gh
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;
    enableZshIntegration = true;

    settings = {
      keybind = [
        "ctrl+shift+p=text:mosh potato-server\\n"
        "ctrl+shift+alt+p=text:mosh --server='NO_TMUX=1 mosh-server' potato-server\\n"
        "ctrl+shift+m=text:mosh potato-server-mc\\n"
        "ctrl+shift+h=text:mosh home-server\\n"
      ];
      shell-integration-features = "cursor,sudo,ssh-env,ssh-terminfo";
    };
  };
}
