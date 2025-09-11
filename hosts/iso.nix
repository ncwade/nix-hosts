{ pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ];

  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
  image.baseName = pkgs.lib.mkForce "nix-base";
  users.users.root.initialHashedPassword = pkgs.lib.mkForce null;
  users.users.root.initialPassword = null;
  virtualisation.vmware.guest.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICy5wxb5jwVx1YDgXpGBVIF50w/i6R+RjuPfi2/btBLW"
  ];
}
