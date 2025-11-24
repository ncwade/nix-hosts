{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ../programs/homebrew.nix
  ];
  nix.enable = false;
  # Used for backwards compatibility. please read the changelog
  # before changing: `darwin-rebuild changelog`.
  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "ncwade";
  users.users.ncwade = {
    name = "ncwade";
    home = "/Users/ncwade";
  };

  programs.zsh.enable = true;
  programs.fish.enable = true;
  environment.systemPackages = [ pkgs.neofetch pkgs.neovim pkgs.starship ];
  security.pam.services.sudo_local.touchIdAuth = true;
}
