{ config, lib, pkgs, modulesPath, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "America/Chicago";
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
  ];
}
