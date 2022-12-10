{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      ../ncwade/home-gui.nix
      ../services/base.nix
      ../services/gui.nix
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usb_storage" "sd_mod" "rtsx_pci_sdmmc" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/8b18ec3b-ea64-47cc-a51a-1aca3156d809";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/CD9C-EE3D";
      fsType = "vfat";
    };

  swapDevices = [ ];

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.useDHCP = false;
  networking.interfaces.wlp2s0.useDHCP = true;
  networking.networkmanager.enable = true;
  networking.hostName = "laptop1";

  system.stateVersion = "21.11";
  system.autoUpgrade.enable = true;
  system.autoUpgrade.allowReboot = false;
}
