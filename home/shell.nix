{
  lib,
  pkgs,
  ...
}:

let
  eza = lib.getExe pkgs.eza;
in
{
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "$EDITOR";
  };

  home.packages = with pkgs; [
    nix-tree
  ];

  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ];
    settings.enter_accept = false;
  };

  programs.bat.enable = true;

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.eza.enable = true;

  programs.zoxide.enable = true;

  programs.zsh = {
    autocd = true;
    enableCompletion = true;

    shellAliases = {
      e = "$EDITOR";
      se = "sudoedit";
      ls = "${eza} --group-directories-first --icons=auto";
      ll = "${eza} -lah --group-directories-first --icons=auto";
      la = "${eza} -a --group-directories-first --icons=auto";
      lt = "${eza} --tree --level=2 --group-directories-first --icons=auto";
      dco = "docker compose";
    };

    shellGlobalAliases = {
      "..." = "../..";
      "...." = "../../..";
      "....." = "../../../..";
    };

    initContent = lib.mkAfter ''
      zstyle ':completion:*' rehash true

      function take() {
        mkdir -p -- "$1" && cd -- "$1"
      }

      function nix-root() {
        local target
        target="$(readlink "$(command -v "$1")")"
        print -r -- "''${target:h:h}"
      }

      function clear-scrollback() {
        printf '\033[H\033[2J\033[3J'
        zle .reset-prompt
      }

      zle -N clear-scrollback
      bindkey '^L' clear-scrollback
    '';
  };
}
