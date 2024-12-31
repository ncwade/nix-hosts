{
  description = "My dotfiles flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    hyprland.url = "github:hyprwm/Hyprland";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, hyprland, disko, ... }@inputs: {
    nixosConfigurations."base-iso-intel" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, modulesPath, ... }: {
          imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
          isoImage.squashfsCompression = "gzip -Xcompression-level 1";
          systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
          hardware.enableAllHardware = true;
          isoImage.isoName = pkgs.lib.mkForce "nix-base-x86_64.iso";
          users.users.root.initialHashedPassword = pkgs.lib.mkForce null;
          users.users.root.initialPassword = null;
          isoImage.makeEfiBootable = true;
          isoImage.makeUsbBootable = true;
          virtualisation.vmware.guest.enable = true;
          boot.loader.systemd-boot.enable = true;
          
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICy5wxb5jwVx1YDgXpGBVIF50w/i6R+RjuPfi2/btBLW"
          ];
          networking = {
            useDHCP = true;
          };
        })
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
    nixosConfigurations."devvm-x86_64" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        disko.nixosModules.disko
        ./hosts/devvm.nix
      ];
    };
    nixosConfigurations."devvm-aarch64" = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = inputs;
      modules = [
        disko.nixosModules.disko
        ./hosts/devvm.nix
      ];
    };
  };
}
