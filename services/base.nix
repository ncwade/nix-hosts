{ config, lib, pkgs, modulesPath, ... }:

{
  time.timeZone = "America/Chicago";
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
  ];
}
