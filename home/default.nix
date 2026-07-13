{
  config,
  pkgs,
  ...
}:

{
  imports = [
    ./linux.nix
    ./shell.nix
    ./tmux.nix
  ];

  home.stateVersion = "24.11";
  programs.home-manager.enable = true;
  xdg.enable = true;

  programs.direnv = {
    enable = true;
    silent = true;
  };

  programs.zsh = {
    enable = true;
    dotDir = "${config.home.homeDirectory}/.config/zsh";

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
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "sudo"
      ];
    };
  };

  home.packages = with pkgs; [
    nixfmt
    tealdeer
    manix
    whois
    bmon
    restic
    autorestic
    ncdu
    zip
    unzip
    nodejs_24
    ripgrep
    htop
    btop
    jq
    rclone
    git-lfs
    fd
    uv
    wget
  ];

  home.sessionPath = [
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
  ];

  programs.git = {
    enable = true;
    settings.core.editor = "vim";
    settings.user = {
      name = "Petr Tsopa";
      email = "petrtsopa03@gmail.com";
    };
  };

  programs.vim = {
    enable = true;
    extraConfig = ''
      set mouse-=a
    '';
  };
}
