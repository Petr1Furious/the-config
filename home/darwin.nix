{
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.isDarwin {
  home.packages = with pkgs; [
    (writeShellScriptBin "timeout" ''
      exec ${coreutils}/bin/timeout "$@"
    '')
    rsync
  ];
}
