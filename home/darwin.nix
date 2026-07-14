{
  lib,
  pkgs,
  ...
}:

lib.mkIf pkgs.stdenv.isDarwin {
  home.packages = [
    (pkgs.writeShellScriptBin "timeout" ''
      exec ${pkgs.coreutils}/bin/timeout "$@"
    '')
  ];
}
