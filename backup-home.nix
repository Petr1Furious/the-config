{
  config,
  lib,
  pkgs,
  ...
}:

{
  backup.locations.root = {
    from = [
      "/root"
    ];
    options = {
      backup = {
        exclude = [
          "/root/.cache"
        ];
      };
    };
  };

  backup.locations.home = {
    from = [
      "/home/petrtsopa"
    ];
    options = {
      backup = {
        exclude = [
          "/home/petrtsopa/.cache"
          "/home/petrtsopa/.vscode-server"
          "/home/petrtsopa/.cursor-server"
          "/home/petrtsopa/.vscode-remote-containers"
        ];
      };
    };
  };
}
