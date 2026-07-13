{
  pkgs,
  ...
}:

{
  imports = [
    ./editor.nix
    ./git.nix
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
    fd
    uv
    wget
    claude-code
  ];

  home.sessionPath = [
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
  ];

}
