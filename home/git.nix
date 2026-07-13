{
  lib,
  pkgs,
  ...
}:

{
  programs = {
    delta = {
      enable = true;
      enableGitIntegration = true;
    };

    git = {
      enable = true;
      lfs.enable = true;

      settings = {
        user = {
          name = "Petr Tsopa";
          email = "petrtsopa03@gmail.com";
        };
      };
    };

    mergiraf = {
      enable = true;
      enableGitIntegration = true;
    };
  };
}
