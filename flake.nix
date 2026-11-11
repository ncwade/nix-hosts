{
  description = "Machine configurations assembled from private user and employer flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-dotfiles.url = "git+ssh://git@github.com/ncwade/nix-dotfiles.git?ref=main";
    nix-dotfiles.inputs.nixpkgs.follows = "nixpkgs";
    defense-unicorns.url = "git+ssh://git@github.com/ncwade/nix-config-defense-unicorns.git?ref=main";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-dotfiles,
      defense-unicorns,
      ...
    }@inputs:
    let
      linuxSystem = "aarch64-linux";
      linuxPkgs = import nixpkgs {
        system = linuxSystem;
        config.allowUnfree = true;
      };
      darwinProfiles = {
        desktop = {
          homeManagerModule = nix-dotfiles.homeManagerModules.desktop;
          macosModule = ./programs/macos.nix;
          extraModules = [ ];
        };
        cli = {
          homeManagerModule = nix-dotfiles.homeManagerModules.cli;
          macosModule = ./programs/macos-cli.nix;
          extraModules = [ ./programs/homebrew-cli.nix ];
        };
      };
      mkDarwinHost =
        hostname:
        {
          extraModules ? [ ],
          profile ? "desktop",
          username ? "ncwade",
        }:
        let
          hostProfile = darwinProfiles.${profile};
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = inputs // {
            inherit username;
          };
          modules = [
            ./hosts/nix-darwin.nix
            hostProfile.macosModule
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.verbose = true;
              home-manager.users.${username} = hostProfile.homeManagerModule;
            }
          ]
          ++ hostProfile.extraModules
          ++ extraModules;
        };
    in
    {
      homeConfigurations.mvm = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          nix-dotfiles.homeManagerModules.mvm
          ./hosts/mvm-home.nix
        ];
      };

      # Personal wiki is opt-in per device, never part of a shared user profile.
      darwinConfigurations = {
        luna = mkDarwinHost "luna" {
          extraModules = [
            {
              homebrew.casks = [ "discord" ];
              home-manager.users.ncwade.imports = [
                nix-dotfiles.homeManagerModules.rex
                defense-unicorns.homeManagerModules.default
              ];
              home-manager.users.ncwade.programs.personalWiki = {
                enable = true;
                remote = "https://github.com/ncwade/personal-wiki.git";
              };
            }
          ];
        };
      } // builtins.mapAttrs mkDarwinHost defense-unicorns.lib.darwinHosts;
    };
}
