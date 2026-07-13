{
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.isLinux {
  programs.zsh.initContent = lib.mkAfter ''
    export LIBVIRT_DEFAULT_URI="qemu:///system"
  '';

  home.packages = with pkgs; [
    gcc
    iotop
    pciutils
  ];
}
