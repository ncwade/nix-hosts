{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      # Keep routine darwin-rebuild runs fast; do explicit brew maintenance separately.
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
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
      "chatgpt"
      "datagrip"
      "docker-desktop"
      "firefox"
      "font-jetbrains-mono"
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "google-chrome"
      "microsoft-edge"
      "notion"
      "orion"
      "postman"
      "rectangle-pro"
      "signal"
      "slack"
      "tailscale-app"
      "wireshark-app"
      "yubico-authenticator"
      "zed"
    ];
  };
}
