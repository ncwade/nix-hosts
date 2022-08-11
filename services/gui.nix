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
  services.xserver = {
    enable = true;
    desktopManager = {
      default = "xfce";
      xterm.enable = false;
      xfce = {
        enable = true;
        #noDesktop = true;
        #enableXfwm = false;
      }
    };
    #windowManager.i3.enable = true;
    xkbOptions = "ctrl:nocaps";
  };

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
}

