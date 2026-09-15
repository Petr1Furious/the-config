{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.backup;
  backend = cfg.backends.backblaze-b2;
  restic = pkgs.writeShellScript "restic-b2-command" ''
    set -euo pipefail
    export AWS_ACCESS_KEY_ID="''${AUTORESTIC_BACKBLAZE_B2_AWS_ACCESS_KEY_ID:?B2 access key is missing}"
    export AWS_SECRET_ACCESS_KEY="''${AUTORESTIC_BACKBLAZE_B2_AWS_SECRET_ACCESS_KEY:?B2 secret key is missing}"
    exec ${lib.getExe pkgs.restic} "$@"
  '';
in
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "restic-yandex" ''
      set -euo pipefail

      export RCLONE_CONFIG=${lib.escapeShellArg "${builtins.dirOf cfg.autoresticYamlPath}/${builtins.baseNameOf (toString cfg.rcloneConfigPath)}"}
      exec ${lib.getExe pkgs.restic} \
        -r ${lib.escapeShellArg "${cfg.backends.yandex.type}:${cfg.backends.yandex.path}"} \
        -p ${lib.escapeShellArg (toString cfg.passwordFilePath)} \
        -o ${lib.escapeShellArg "rclone.program=${lib.getExe pkgs.rclone}"} \
        "$@"
    '')
    (pkgs.writeShellScriptBin "restic-b2" ''
      set -euo pipefail

      exec ${pkgs.systemd}/bin/systemd-run \
        --quiet --wait --collect --service-type=exec --expand-environment=no \
        --pty --pipe --working-directory="$PWD" \
        --property=UMask=0077 \
        ${lib.escapeShellArg "--property=EnvironmentFile=${backend.environmentFilePath}"} \
        ${lib.escapeShellArg "--setenv=RESTIC_REPOSITORY=${backend.type}:${backend.path}"} \
        ${lib.escapeShellArg "--setenv=RESTIC_PASSWORD_FILE=${cfg.passwordFilePath}"} \
        ${
          lib.optionalString (cfg.cacheDir != null) (
            lib.escapeShellArg "--setenv=RESTIC_CACHE_DIR=${cfg.cacheDir}"
          )
        } \
        ${restic} "$@"
    '')
  ];
}
