{
  description = "My dotfiles flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    rex.url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
    rex.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }@inputs:
    let
      linuxSystem = "aarch64-linux";
      linuxPkgs = import nixpkgs {
        system = linuxSystem;
        config.allowUnfree = true;
      };
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
      homeConfigurations.mvm = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./home-manager/mvm.nix
        ];
      };

      # Personal wiki is opt-in per device, never part of a shared user profile.
      darwinConfigurations."luna" = mkDarwinHost "luna" {
        extraModules = [
          {
            homebrew.casks = [ "discord" ];
            home-manager.users.ncwade.imports = [
              inputs.rex.homeManagerModules.default
              ./programs/rex.nix
            ];
            home-manager.users.ncwade.programs.personalWiki = {
              enable = true;
              remote = "https://github.com/ncwade/personal-wiki.git";
            };
          }
        ];
      };
      darwinConfigurations."retired-work-mac" = mkDarwinHost "retired-work-mac" { };
      darwinConfigurations."work-mac" = mkDarwinHost "work-mac" {
        username = "workuser";
        homeManagerModule = ./home-manager/ncwade-cli.nix;
        macosModule = ./programs/macos-cli.nix;
        extraModules = [ ./programs/homebrew-cli.nix ];
      };
    };
}
