{lib, ...}:

{
  nixpkgs.config.allowUnfree = true;

  # high res displays
  hardware.video.hidpi.enable = lib.mkDefault true;
  services.xserver.enable = true;

  services.xserver.xkbOptions = "ctrl:nocaps";

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
}

