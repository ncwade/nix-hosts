{ config, lib, pkgs, modulesPath, ... }:

{
  time.timeZone = "America/Chicago";
  environment.systemPackages = with pkgs; [
    vim
    curl
  ];
}
