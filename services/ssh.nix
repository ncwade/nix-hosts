{ config, lib, pkgs, modulesPath, ... }:

{
  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    passwordAuthentication = false;
  };
}
