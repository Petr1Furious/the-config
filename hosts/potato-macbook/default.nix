{ pkgs, ... }:

{
  imports = [ ../../modules/common/nix.nix ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  nix = {
    package = pkgs.lix;
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;
    linux-builder.enable = true;
  };

  system.primaryUser = "petrtsopa";
  users.users.petrtsopa.home = "/Users/petrtsopa";

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;

      ShowPathbar = true;
      ShowStatusBar = true;

      FXPreferredViewStyle = "Nlsv";
      NewWindowTarget = "Home";
      QuitMenuItem = true;
      _FXShowPosixPathInTitle = true;
    };

    screencapture = {
      location = "~/Pictures/Screenshots";
      type = "png";
      show-thumbnail = false;
    };

    NSGlobalDomain = {
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };

    hitoolbox.AppleFnUsageType = "Do Nothing";
    screensaver.askForPasswordDelay = 10;
  };

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall";
    };

    casks = [
      "google-chrome"
      "iterm2"
      "visual-studio-code"
      "notunes"
      "raycast"
      "iina"
      "orbstack"
      "bettertouchtool"
    ];
  };

  system.stateVersion = 6;
}
