{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      ../services/common.nix
      ../services/base.nix
      ../services/gui.nix
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/857f40e1-e1bc-46fc-8998-56eb76664c67";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/EC58-2D8F";
      fsType = "vfat";
    };

  swapDevices = [ ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = false;
  networking.interfaces.enp6s0.useDHCP = true;
  networking.interfaces.wlp5s0.useDHCP = true;
  networking.hostName = "workstation1";

  services.xserver.videoDrivers = [ "nvidia" ];
}
