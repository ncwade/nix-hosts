{
  pkgs,
  username,
  ...
}:

{
  imports = [
    ../programs/homebrew.nix
    ../programs/ssh.nix
  ];
  nix.enable = false;
  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = username;
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  programs.zsh.enable = true;
  programs.fish.enable = true;
  environment.systemPackages = [
    pkgs.fastfetch
    pkgs.neovim
    pkgs.starship
  ];
  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
  ];
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };
}
