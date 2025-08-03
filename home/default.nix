{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;

  programs.direnv = {
    enable = true;
    silent = true;
  };

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";

    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;
    history = {
      path = "${config.xdg.dataHome}/zsh/history";
      extended = true;
    };

    plugins = [
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
      {
        name = "zsh-peco-history";
        src = pkgs.fetchFromGitHub {
          owner = "jimeh";
          repo = "zsh-peco-history";
          rev = "73615968d46cf172931946b00f89a59da0c124a5";
          hash = "sha256-lEgisjuLrnetIUG0fXl9vH3/ZHgpyQviy7rJazCkMTs=";
        };
      }
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
      ];
    };
  };

  programs.git = {
    enable = true;
    userName = "Petr Tsopa";
    userEmail = "petrtsopa03@gmail.com";
  };

  programs.vim = {
    enable = true;
    extraConfig = ''
      set mouse-=a
    '';
  };
}
