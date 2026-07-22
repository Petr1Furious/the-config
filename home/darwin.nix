{
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.isDarwin {
  home.packages = with pkgs; [
    (writeShellScriptBin "timeout" ''
      exec ${coreutils}/bin/timeout "$@"
    '')
    rsync
  ];

  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;
    enableZshIntegration = true;

    settings = {
      keybind = [
        "ctrl+shift+p=text:ssh potato-server\\n"
        "ctrl+shift+m=text:ssh potato-server-mc\\n"
        "ctrl+shift+h=text:ssh home-server\\n"
      ];
      shell-integration-features = "cursor,sudo,ssh-env,ssh-terminfo";
    };
  };
}
