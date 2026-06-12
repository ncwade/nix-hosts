{ ... }:
{
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";
    taps = [
      "chainguard-dev/tap"
      "work-org/tap"
    ];
    brews = [
      "awscli"
      "chainguard-dev/tap/chainctl"
      "checkov"
      "gopls"
      "helm"
      "krew"
      "libpq"
      "lua"
      "markdownlint-cli"
      "opa"
      "opensc"
      "pkcs11-tools"
      "postgresql@14"
      "redis"
      "tailscale"
      "telnet"
      "work-org/tap/zarf"
      "trivy"
      "wireshark"
      "ykman"
    ];
    casks = [
      "1password"
      "1password-cli"
      "beyond-compare"
      "datagrip"
      "docker-desktop"
      "firefox"
      "font-jetbrains-mono"
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "microsoft-edge"
      "notion"
      "orion"
      "postman"
      "rectangle-pro"
      "signal"
      "slack"
      "wireshark-app"
      "yubico-authenticator"
      "zed"
    ];
  };
}
