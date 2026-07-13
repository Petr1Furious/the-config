{
  description = "My NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      agenix,
      home-manager,
      home-manager-unstable,
      vscode-server,
      nixarr,
      disko,
      nix-darwin,
    }:
    let
      system = "x86_64-linux";
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        secrets = ./secrets;
      };
    in
    {
      nixosConfigurations.home-server = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          ./hosts/home-server
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.petrtsopa = {
              imports = [ ./home ];
              shell.autoAttachTmux = true;
            };
          }
        ];
      };

      nixosConfigurations.potato-server = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          ./hosts/potato-server
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.petrtsopa = {
              imports = [ ./home ];
              shell.autoAttachTmux = true;
            };
          }
        ];
      };

      darwinConfigurations."Petrs-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        specialArgs = specialArgs // {
          pkgs-unstable = import nixpkgs-unstable {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
        };
        modules = [
          ./hosts/potato-macbook
          home-manager-unstable.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.petrtsopa = ./home;
          }
        ];
      };
    };
}
