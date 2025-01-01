{
  modulesPath,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./devvm-disko.nix
    ../services/common.nix
    ../services/base.nix
    ../services/gui.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICy5wxb5jwVx1YDgXpGBVIF50w/i6R+RjuPfi2/btBLW SSH Key"
  ];
  networking = {
    hostName = "devvm";
    useDHCP = true;
  };

  virtualisation.vmware.guest.enable = true;

  system.stateVersion = "24.05";
}
