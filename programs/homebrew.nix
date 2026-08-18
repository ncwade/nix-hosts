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
    ];
    brews = [
      # Keep tools whose Nix packages are missing or need macOS integration.
      "chainguard-dev/tap/chainctl"
      # The current nixpkgs build depends on insecure python3.14-ecdsa-0.19.2.
      "checkov"
      "opensc"
      "pkcs11-tools"
      "wireshark"
    ];
    casks = [
      "1password"
      # Keep the signed upstream binary for desktop-app integration.
      "1password-cli"
      "beyond-compare"
      "chatgpt"
      "datagrip"
      "docker-desktop"
      "firefox"
      # The current nixpkgs source hash is stale, so this derivation cannot build.
      "font-jetbrains-mono"
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
