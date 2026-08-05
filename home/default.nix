{
  pkgs,
  pkgs-unstable,
  ...
}:

{
  imports = [
    ./editor.nix
    ./git.nix
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

  home.packages = with pkgs; [
    bmon
    btop
    pkgs-unstable.claude-code
    fd
    htop
    jq
    manix
    ncdu
    nix-tree
    nixfmt
    nodejs_26
    ripgrep
    rsync
    tealdeer
    tree-sitter
    unzip
    uv
    wget
    whois
    zip
  ];

  home.sessionPath = [
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
  ];

}
