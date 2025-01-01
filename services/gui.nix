{lib, ...}:

{
  nixpkgs.config.allowUnfree = true;
  services.xserver.enable = true;
  services.xserver.xkbOptions = "ctrl:nocaps";
}

