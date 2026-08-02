{ ... }:

{
  imports = [ ../../modules/darwin/common.nix ];

  nix.linux-builder.enable = true;

  system.primaryUser = "petrtsopa";
  users.users.petrtsopa.home = "/Users/petrtsopa";

  homebrew = {
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };

    casks = [
      "google-chrome"
      "visual-studio-code"
      "notunes"
      "raycast"
      "iina"
      "orbstack"
      "bettertouchtool"
      "tailscale-app"
    ];
  };
}
