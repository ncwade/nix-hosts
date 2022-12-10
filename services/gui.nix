{ config, lib, pkgs, modulesPath, ... }:

{
  nixpkgs.config.allowUnfree = true;

  # high res displays
  hardware.video.hidpi.enable = lib.mkDefault true;
  services.xserver.enable = true;

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.xserver.xkbOptions = "ctrl:nocaps";

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
}

