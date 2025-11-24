{ ... }:
{
  homebrew = {
    enable = true;
    taps = [
      "work-org/tap"
    ];
    brews = [
      "helm"
      "awscli"
      "markdownlint-cli"
      "work-org/tap/zarf"
    ];
    casks = [
      "zed"
      "ghostty"
      "notion"
      "slack"
      "microsoft-edge"
      "1password"
      "1password-cli"
      "datagrip"
      "docker-desktop"
      "font-jetbrains-mono"
      "font-jetbrains-mono-nerd-font"
      "keepingyouawake"
      "vagrant"
      "vagrant-vmware-utility"
      "vagrant"
      "rectangle-pro"
      "yubico-authenticator"
    ];
  };
}
