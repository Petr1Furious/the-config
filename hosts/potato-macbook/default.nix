{ ... }:

{
  imports = [ ../../modules/darwin/common.nix ];

  system.primaryUser = "petrtsopa";
  users.users.petrtsopa.home = "/Users/petrtsopa";

  system.defaults.CustomUserPreferences."net.sourceforge.skim-app.skim" = {
    SKTeXEditorPreset = "";
    SKTeXEditorCommand = "/etc/profiles/per-user/petrtsopa/bin/nvim";
    SKTeXEditorArguments = ''--headless -c "VimtexInverseSearch %line '%file'"'';
  };

  homebrew = {
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };

    casks = [
      "google-chrome"
      "visual-studio-code"
      "macshot"
      "notunes"
      "raycast"
      "iina"
      "kde-connect"
      "orbstack"
      "stats"
      "tailscale-app"
      "linearmouse"
      "sfm"
      "skim"
    ];
  };
}
