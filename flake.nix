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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      agenix,
      home-manager,
      vscode-server,
      nixarr,
      disko,
    }:
    let
      system = "x86_64-linux";
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      # Arguments handed to every host's modules. `secrets` is the agenix
      # secrets directory as a path, so modules reference secrets by name
      # (secrets + "/foo.age") regardless of where they live in the tree.
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgsUnstable;
        secrets = ./secrets;
      };
    in
    {
      # Home box: NVIDIA + virtualisation. (agenix comes from modules/common/base.nix;
      # input-coupled service modules self-import their flake module.)
      nixosConfigurations.home-server = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          ./hosts/home-server
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.petrtsopa = ./home;
          }
        ];
      };

      # OVH box: the service stack, reached from Russia via the Selectel relay
      # (see hosts/potato-server/relay.nix).
      nixosConfigurations.potato-server = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          ./hosts/potato-server
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.petrtsopa = ./home;
          }
        ];
      };
    };
}
