{ ... }:

{
  imports = [
    ../default.nix
    ../linux.nix
  ];

  home.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/docker.sock";
}
