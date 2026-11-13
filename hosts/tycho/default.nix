{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware.nix
    ./books.nix
    ./nas1.nix
    ./rex.nix
  ];

  networking.hostName = "tycho";
  networking.useDHCP = lib.mkDefault true;
  time.timeZone = "America/Chicago";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  users.users.ncwade = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    # Luna's existing 1Password SSH key; private material stays on Luna.
    # Set a password during installation for sudo and optional console login.
    openssh.authorizedKeys.keyFiles = [ ./admin.pub ];
  };
  services.openssh = {
    enable = true;
    # LAN access is required for headless setup before tailnet enrollment.
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "ncwade" ];
    };
  };

  services.avahi = {
    enable = true;
    openFirewall = true;
    settings.publish = {
      disable-publishing = false;
      publish-addresses = true;
    };
  };
  # Avoid a startup race with openresolv's Avahi SIGHUP notification.
  systemd.services.avahi-daemon = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "resolvconf.service"
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "none";
  };
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [ 22 ];

  environment.systemPackages = with pkgs; [
    curl
    neovim
    nfs-utils
    rsync
  ];
  services.fstrim.enable = true;
  services.fwupd.enable = true;
  zramSwap.enable = true;
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # Initial installation compatibility version; do not change on upgrades.
  system.stateVersion = "26.05";
}
