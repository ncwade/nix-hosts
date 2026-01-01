{
  pkgs,
  ...
}:

{
  imports = [
    ../programs/homebrew.nix
  ];
  nix.enable = false;
  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "ncwade";
  users.users.ncwade = {
    name = "ncwade";
    home = "/Users/ncwade";
  };

  programs.zsh.enable = true;
  programs.fish.enable = true;
  environment.systemPackages = [
    pkgs.neofetch
    pkgs.neovim
    pkgs.starship
  ];
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };
}
