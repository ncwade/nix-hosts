{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ../services/common.nix
    ../services/base.nix
    ../services/ssh.nix
    ../services/dns.nix
  ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "rock1";
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;
  boot.initrd.availableKernelModules = [ "usbhid" ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
      fsType = "ext4";
    };
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  system.stateVersion = "21.11";
}
