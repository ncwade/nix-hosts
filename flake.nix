{
  description = "My dotfiles flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.url = "github:hyprwm/Hyprland";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, hyprland, disko, nix-darwin, home-manager, ... }@inputs: {
    isoConfigs."base-iso-intel" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/iso.nix
      ];
    };
    isoConfigs."base-iso-arm" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/iso.nix
      ];
    };
    nixosConfigurations."laptop1" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        hyprland.nixosModules.default
        {programs.hyprland.enable = true;}
        ./hosts/laptop1.nix
      ];
    };
    nixosConfigurations."rock1" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/rock1.nix
      ];
    };
    nixosConfigurations."rock2" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/rock2.nix
      ];
    };
    nixosConfigurations."workstation1" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        ./hosts/workstation1.nix
      ];
    };
    nixosConfigurations."devvm-intel" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        disko.nixosModules.disko
        ./hosts/devvm.nix
      ];
    };
    nixosConfigurations."devvm-arm" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = inputs;
      modules = [
        disko.nixosModules.disko
        ./hosts/devvm.nix
      ];
    };
    darwinConfigurations."sungrave" = nix-darwin.lib.darwinSystem {
      modules = [
        ./hosts/sungrave.nix
	home-manager.darwinModules.home-manager  {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.verbose = true;
	  home-manager.users.ncwade = import ./home-manager/ncwade.nix;
        }
      ];
    };
  };
}
