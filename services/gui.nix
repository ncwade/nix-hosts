{ config, lib, pkgs, modulesPath, ... }:

{
  nixpkgs.config.allowUnfree = true;

  # high res displays
  hardware.video.hidpi.enable = lib.mkDefault true;
  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages = (with pkgs; [
    gnome-photos
    gnome-tour
    gnome-text-editor
    xterm
  ]) ++ (with pkgs.gnome; [
    cheese # webcam tool
    gnome-music
    gedit # text editor
    epiphany # web browser
    geary # email reader
    gnome-characters
    tali # poker game
    iagno # go game
    hitori # sudoku game
    atomix # puzzle game
    yelp # Help view
    gnome-contacts
    gnome-initial-setup
    gnome-weather
    gnome-clocks
    gnome-maps
    gnome-calculator
    totem
    gnome-terminal
  ]);
  services.xserver.xkbOptions = "ctrl:nocaps";

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
}

