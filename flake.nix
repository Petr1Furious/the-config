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
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      home-manager-unstable,
      disko,
      nix-darwin,
      ...
    }:
    let
      mkPkgs =
        source: system:
        import source {
          inherit system;
          config.allowUnfree = true;
        };

      mkPkgsUnstable = mkPkgs nixpkgs-unstable;

      commonSpecialArgs = {
        inherit inputs;
      };

      mkNixosServer =
        {
          hostModules,
          homeModules ? [ ],
        }:
        let
          system = "x86_64-linux";
          specialArgs = commonSpecialArgs // {
            pkgs-unstable = mkPkgsUnstable system;
            secrets = ./secrets;
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = hostModules ++ [
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = specialArgs;
              home-manager.users.petrtsopa.imports = [
                ./home/profiles/nixos-server.nix
              ]
              ++ homeModules;
            }
          ];
        };

      mkDarwin =
        {
          hostModule,
          homeModule,
          user,
        }:
        let
          system = "aarch64-darwin";
          specialArgs = commonSpecialArgs // {
            pkgs-unstable = mkPkgsUnstable system;
          };
        in
        nix-darwin.lib.darwinSystem {
          inherit specialArgs;
          modules = [
            hostModule
            home-manager-unstable.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = specialArgs;
              home-manager.users.${user} = homeModule;
            }
          ];
        };

    in
    {
      nixosConfigurations.home-server = mkNixosServer {
        hostModules = [ ./hosts/home-server ];
        homeModules = [
          {
            programs.zsh.initContent = nixpkgs.lib.mkAfter ''
              export LIBVIRT_DEFAULT_URI="qemu:///system"
            '';
          }
        ];
      };

      nixosConfigurations.potato-server = mkNixosServer {
        hostModules = [
          ./hosts/potato-server
          disko.nixosModules.disko
        ];
      };

      darwinConfigurations."Petrs-MacBook-Pro" = mkDarwin {
        hostModule = ./hosts/potato-macbook;
        homeModule = ./home/profiles/personal-mac.nix;
        user = "petrtsopa";
      };

    };
}
