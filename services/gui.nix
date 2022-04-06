{ config, lib, pkgs, modulesPath, ... }:

{
  nixpkgs.config.allowUnfree = true;

  nixpkgs.config = {
    chromium = {
      enableWideVine = true;
    };
  };

  # high res displays
  hardware.video.hidpi.enable = lib.mkDefault true;
  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the Plasma 5 Desktop Environment.
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.xkbOptions = "ctrl:nocaps";

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
}

