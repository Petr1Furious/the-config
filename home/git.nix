{ ... }:

{
  programs = {
    delta = {
      enable = true;
      enableGitIntegration = true;
    };

    git = {
      enable = true;
      lfs.enable = true;
    };

    mergiraf = {
      enable = true;
      enableGitIntegration = true;
    };
  };
}
