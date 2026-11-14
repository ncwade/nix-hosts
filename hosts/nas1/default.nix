{ lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./disk-config.nix
    ./documents.nix
    ./bookorbit-backup.nix
    ./rex.nix
  ];

  # Observed on nas1: Atom C3558, 16 GiB RAM, AHCI disks, Intel X553 NICs.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "usb_storage" "sd_mod" ];
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  # Use the default kernel, which must evaluate/build with the selected ZFS.
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "8f53bd72";
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;
  # The documents service imports by GUID and mounts only the required dataset.
  boot.zfs.extraPools = [ ];
  personal.nas1.documents.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nas1";
  networking.useDHCP = false;
  networking.useNetworkd = true;
  # Keep the existing DHCP identity even if interface naming changes.
  services.resolved.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "d0:50:99:fb:10:13";
    networkConfig.DHCP = "ipv4";
    dhcpV4Config.ClientIdentifier = "mac";
  };
  time.timeZone = "America/Chicago";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  # Existing nas1 public login key; private keys never enter the Nix store.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICy5wxb5jwVx1YDgXpGBVIF50w/i6R+RjuPfi2/btBLW"
  ];

  # Reserve the existing document ownership before importing any data.
  users.groups.docs.gid = 1001;
  users.users.docs = {
    isSystemUser = true;
    uid = 1001;
    group = "docs";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;
  services.journald.settings.Journal.SystemMaxUse = "128M";
  zramSwap.enable = true;
  environment.systemPackages = with pkgs; [ rsync smartmontools ipmitool ];
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # Set at this machine's initial NixOS installation; retain on upgrades.
  system.stateVersion = "26.05";
}
