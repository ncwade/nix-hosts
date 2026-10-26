{
  description = "My dotfiles flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      disko,
      ...
    }@inputs:
    let
      system = "aarch64-darwin";
      linuxSystem = "aarch64-linux";
      serverSystem = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
      linuxPkgs = import nixpkgs {
        system = linuxSystem;
        config.allowUnfree = true;
      };
      corpUbuntuVm = pkgs.callPackage ./packages/corp-ubuntu-vm.nix {};
      morningStar = pkgs.callPackage ./infra/retired-cloud-host {};
      mkDarwinHost =
        hostname:
        {
          extraModules ? [ ],
          homeManagerModule ? ./home-manager/ncwade.nix,
          macosModule ? ./programs/macos.nix,
          username ? "ncwade",
        }:
        nix-darwin.lib.darwinSystem {
          specialArgs = inputs // {
            inherit username;
          };
          modules = [
            ./hosts/nix-darwin.nix
            macosModule
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.verbose = true;
              home-manager.users.${username} = import homeManagerModule;
            }
          ]
          ++ extraModules;
        };
    in
    {
      packages.${system} = {
        corp-ubuntu-vm = corpUbuntuVm;
        retired-cloud-host = morningStar;
      };
      apps.${system} = {
        corp-ubuntu-vm = {
          type = "app";
          program = "${corpUbuntuVm}/bin/corp-ubuntu-vm";
        };
        retired-cloud-host = {
          type = "app";
          program = "${morningStar}/bin/retired-cloud-host";
        };
      };
      homeConfigurations.corp-ubuntu-vm = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./home-manager/corp-ubuntu-vm.nix
        ];
      };
      homeConfigurations.mvm = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./home-manager/mvm.nix
        ];
      };

      darwinConfigurations."luna" = mkDarwinHost "luna" { };
      darwinConfigurations."retired-work-mac" = mkDarwinHost "retired-work-mac" { };
      darwinConfigurations."work-mac" = mkDarwinHost "work-mac" {
        username = "workuser";
        homeManagerModule = ./home-manager/ncwade-cli.nix;
        macosModule = ./programs/macos-cli.nix;
        extraModules = [ ./programs/homebrew-cli.nix ];
      };

      nixosConfigurations.retired-router = nixpkgs.lib.nixosSystem {
        system = serverSystem;
        specialArgs = inputs;
        modules = [
          disko.nixosModules.disko
          ./hosts/retired-router.nix
        ];
      };
    };
}
