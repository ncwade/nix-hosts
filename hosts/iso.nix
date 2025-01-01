{ pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ];

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
  hardware.enableAllHardware = true;
  isoImage.isoName = pkgs.lib.mkForce "nix-base.iso";
  users.users.root.initialHashedPassword = pkgs.lib.mkForce null;
  users.users.root.initialPassword = null;
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  virtualisation.vmware.guest.enable = true;
  boot.loader.systemd-boot.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICy5wxb5jwVx1YDgXpGBVIF50w/i6R+RjuPfi2/btBLW"
  ];
  networking = {
    useDHCP = true;
  };
}
