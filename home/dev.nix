{ pkgs, ... }:

{
  home.packages = with pkgs; [
    manix
    nix-tree
    nixfmt
    nodejs_26
    tree-sitter
    uv
  ];
}
