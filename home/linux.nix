{
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.isLinux {
  home.packages = with pkgs; [
    gcc
    iotop
    pciutils
  ];
}
