{
  description = "Machine configurations assembled from private user and employer flakes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rex.url = "https://pkgs.superlogical.com/rex/nix/preview/0.1.0-preview.12.tar.gz";
    rex.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
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
      rex,
      disko,
      nix-darwin,
      home-manager,
      nix-dotfiles,
      defense-unicorns,
      ...
    }@inputs:
    let
      tychoSystem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          rex.nixosModules.default
          ./hosts/tycho
        ];
      };
      tychoInstaller = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit tychoSystem; };
        modules = [ ./installer/tycho.nix ];
      };
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
      nixosConfigurations.tycho = tychoSystem;
      nixosConfigurations.nas1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          rex.nixosModules.default
          disko.nixosModules.disko
          ./hosts/nas1
        ];
      };
      nixosConfigurations.tycho-installer = tychoInstaller;
      packages = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (_: {
        tycho-iso = tychoInstaller.config.system.build.isoImage;
      });

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
              homebrew.casks = [
                "discord"
                "steam"
              ];
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
      }
      // builtins.mapAttrs mkDarwinHost defense-unicorns.lib.darwinHosts;
    };
}
