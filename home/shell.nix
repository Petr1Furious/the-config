{
  config,
  lib,
  pkgs,
  ...
}:

let
  eza = lib.getExe pkgs.eza;
in
{
  home.packages = with pkgs; [
    nix-tree
  ];

  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ];
    settings.enter_accept = false;
  };

  programs.bat.enable = true;

  programs.eza.enable = true;

  programs.zoxide.enable = true;

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    autocd = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;
    history = {
      path = "${config.xdg.dataHome}/zsh/history";
      extended = true;
    };

    plugins = [
      {
        name = "omz-urlfunctions";
        src = ./omz-urlfunctions;
        file = "omz-urlfunctions.zsh";
      }
    ]
    ++ (builtins.map
      (name: {
        name = "omz-lib-${name}";
        src = pkgs.oh-my-zsh;
        file = "share/oh-my-zsh/lib/${name}.zsh";
      })
      [
        "clipboard"
        "compfix"
        "completion"
        "git"
        "history"
        "key-bindings"
        "termsupport"
      ]
    )
    ++ (builtins.map
      (name: {
        name = "omz-plugin-${name}";
        src = pkgs.oh-my-zsh;
        file = "share/oh-my-zsh/plugins/${name}/${name}.plugin.zsh";
      })
      [
        "git"
        "sudo"
      ]
    )
    ++ [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = ./p10k;
        file = "p10k.zsh";
      }
    ];

    shellAliases =
      let
        ls = "${eza} --group-directories-first -ag --icons always";
        ll = "${ls} -l";
        lt = "${ls} --tree --level=2";
      in
      {
        e = "$EDITOR";
        se = "sudoedit";
        ls = ls;
        ll = ll;
        lt = lt;
        sls = "sudo ${ls}";
        sll = "sudo ${ll}";
        slt = "sudo ${lt}";
        dco = "docker compose";
        gst = "git status";
        gco = "git checkout";
        gcm = "git commit -m";
        gcma = "git commit -am";
        gpl = "git pull";
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
