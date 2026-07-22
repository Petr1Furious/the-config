{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.shell.autoAttachTmux = lib.mkEnableOption "automatic tmux attachment for SSH sessions";

  config = {
    programs.tmux = {
      enable = true;
      baseIndex = 1;
      clock24 = true;
      historyLimit = 50000;
      keyMode = "vi";
      mouse = true;
      terminal = "tmux-256color";
      plugins = [ pkgs.tmuxPlugins.sensible ];
      extraConfig = ''
        set -s set-clipboard on
        set -g renumber-windows on
        setw -g pane-base-index 1
      '';
    };

    programs.zsh.initContent = lib.mkIf config.shell.autoAttachTmux (
      lib.mkBefore ''
        if [[ -o interactive && -n "$SSH_TTY" && -z "$TMUX" ]]; then
          exec ${lib.getExe pkgs.tmux} new-session -A -s main
        fi
      ''
    );
  };
}
