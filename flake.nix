{
  description = "My dotfiles flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      ...
    }@inputs:
    {
      darwinConfigurations."luna" = nix-darwin.lib.darwinSystem {
        specialArgs = inputs;
        modules = [
          ./hosts/nix-darwin.nix
          ./programs/macos.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.verbose = true;
            home-manager.users.ncwade = import ./home-manager/ncwade.nix;
          }
        ];
      };
      darwinConfigurations."sungrave" = nix-darwin.lib.darwinSystem {
        specialArgs = inputs;
        modules = [
          ./hosts/nix-darwin.nix
          ./programs/macos.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.verbose = true;
            home-manager.users.ncwade = import ./home-manager/ncwade.nix;
          }
        ];
      };
    };
}
