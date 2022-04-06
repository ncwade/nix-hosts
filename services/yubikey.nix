{ config, lib, pkgs, ... }:

{
  services.udev.packages = with pkgs; [ yubikey-personalization ];

  # For smartcards
  services.pcscd.enable = true;

  # Use gpg-agent instead of system-wide ssh-agent
  programs.ssh.startAgent = false;
  programs.ssh.askPassword = "${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass";
  programs.gnupg = {
    agent.enable = true;
    agent.enableSSHSupport = true;
    agent.enableExtraSocket = true;
    agent.enableBrowserSocket = true;
    dirmngr.enable = true;
  };

  security.pam.services."sshd".u2fAuth = false;
  security.pam.services."sudo".u2fAuth = false;

  environment.systemPackages = with pkgs; [
    yubico-piv-tool
    yubikey-personalization
    gnupg
    pass
  ];
}
