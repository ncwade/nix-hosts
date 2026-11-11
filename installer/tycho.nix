{
  config,
  lib,
  pkgs,
  modulesPath,
  tychoSystem,
  ...
}:

let
  # Only repository configuration goes on the USB, never .git or local output.
  configSource = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../flake.nix
      ../flake.lock
      ../hosts
      ../programs
      ../scripts
      ../installer
      ../docs
      ../README.md
    ];
  };
  installTycho = pkgs.writeShellApplication {
    name = "install-tycho";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      gnugrep
      parted
      dosfstools
      e2fsprogs
      nixos-install
      nixos-enter
      config.system.build.nixos-generate-config
      systemd
    ];
    text = ''
      export TYCHO_SYSTEM=${tychoSystem.config.system.build.toplevel}
      export TYCHO_CONFIG=${configSource}
    ''
    + builtins.readFile ./install-tycho.sh;
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  networking.hostName = "tycho-installer";
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # The target uses ext4 and remote NFS; avoid the generic ISO's ZFS module,
  # which does not support every release of the latest kernel.
  boot.supportedFilesystems.zfs = lib.mkForce false;
  hardware.cpu.amd.updateMicrocode = true;
  image.baseName = lib.mkForce "tycho-installer-x86_64";
  isoImage.volumeID = "TYCHO-INSTALL";
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  # The USB carries the complete target system, so installation is offline.
  isoImage.storeContents = [ tychoSystem.config.system.build.toplevel ];
  environment.systemPackages = [
    installTycho
    pkgs.tmux
  ];
  # Boot into a live environment. Installation starts only when requested over
  # SSH (or manually at a console); merely booting the USB never erases a disk.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = lib.mkForce "no";
      AllowUsers = [ "nixos" ];
    };
  };
  users.users.nixos.openssh.authorizedKeys.keyFiles = [ ../hosts/tycho/admin.pub ];
  services.avahi = {
    enable = true;
    openFirewall = true;
    settings.publish = {
      disable-publishing = false;
      publish-addresses = true;
    };
  };
  # Let initial resolver updates finish before Avahi creates its PID file;
  # openresolv can otherwise send SIGHUP before Avahi installs its handler.
  systemd.services.avahi-daemon = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "resolvconf.service"
    ];
  };
}
