{ pkgs, ... }:

{
  imports = [ ../common/nix.nix ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  nix = {
    package = pkgs.lix;
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
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

    hitoolbox.AppleFnUsageType = "Do Nothing";
    screensaver.askForPasswordDelay = 10;
  };

  homebrew = {
    enable = true;
    enableZshIntegration = true;
  };

  system.stateVersion = 6;
}
