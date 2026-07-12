{ inputs, ... }:

{
  imports = [ inputs.vscode-server.nixosModules.default ];

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.cursor-server"
    ];
  };
}
