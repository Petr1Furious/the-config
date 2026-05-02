{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-kernel.url = "github:nixos/nixpkgs/1267bb4920d0fc06ea916734c11b0bf004bbe17e";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nixpkgs-kernel,
      agenix,
      home-manager,
      vscode-server,
      nixarr,
    }:
    let
      system = "x86_64-linux";
      # nixarr references services.shelfmark
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.potato-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            nixpkgs.overlays = [
              (_final: prev: {
                shelfmark = pkgsUnstable.shelfmark;
              })
            ];
          }
          "${nixpkgs-unstable}/nixos/modules/services/misc/shelfmark.nix"
          ./configuration.nix
          agenix.nixosModules.default
          {
            environment.systemPackages = [ agenix.packages.${system}.default ];
          }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.petrtsopa = ./home;
          }
          vscode-server.nixosModules.default
          nixarr.nixosModules.default
        ];
        specialArgs = {
          pkgs-unstable = import nixpkgs-unstable {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
          pkgs-kernel = import nixpkgs-kernel {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
        };
      };
    };
}
