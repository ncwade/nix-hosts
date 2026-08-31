{ lib, ... }:

{
  # CLI-only Homebrew: keep signed CLI tools and fonts, skip GUI casks.
  homebrew.casks = lib.mkForce [
    "1password-cli"
    "font-jetbrains-mono"
  ];
}
