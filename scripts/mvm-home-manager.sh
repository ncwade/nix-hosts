#!/usr/bin/env bash
set -euo pipefail

# This script is invoked by mvm while it provisions its golden base. The Nix
# source below is a staged local Git flake, so keep this repository trusted.
flake='git+file:///Users/ncwade/src/github.com/ncwade/nix-hosts#homeConfigurations.mvm.activationPackage'
generation="$HOME/.local/state/mvm-home-manager/generation"
nix_installer_version="v3.24.3"
nix_installer_url="https://install.determinate.systems/nix/tag/${nix_installer_version}/nix-installer-aarch64-linux"
nix_installer_sha256="9f57d5948639498baca3f20fbc619ca22dc8ea6d101691761f20cc957d04a13c"

if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  installer_dir="$(mktemp -d)"
  trap 'rm -rf -- "$installer_dir"' EXIT
  installer="$installer_dir/nix-installer"
  curl --proto '=https' --tlsv1.2 -sSf -L -o "$installer" "$nix_installer_url"
  if ! printf '%s  %s\n' "$nix_installer_sha256" "$installer" | sha256sum -c - >/dev/null 2>&1; then
    printf 'error: SHA-256 checksum verification failed for %s\n' "$nix_installer_url" >&2
    exit 1
  fi
  chmod 0700 "$installer"
  "$installer" install --no-confirm
  rm -rf -- "$installer_dir"
  trap - EXIT
fi

# Bootstrap git from the distro archive so Nix can evaluate the local git+file
# flake; Ubuntu/Debian archives drop superseded package revisions on security
# updates, and Home Manager activates the flake-locked git afterward.
if ! command -v git >/dev/null 2>&1; then
  sudo apt-get -o DPkg::Lock::Timeout=300 update -qq
  sudo apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends git
fi

sudo install -d -m 0755 /etc/nix
sudo touch /etc/nix/nix.conf
if ! grep -q '^experimental-features = .*nix-command.*flakes' /etc/nix/nix.conf; then
  printf '\nexperimental-features = nix-command flakes\n' | sudo tee -a /etc/nix/nix.conf >/dev/null
fi
sudo systemctl enable --now nix-daemon.service >/dev/null 2>&1 || true

. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
if [ ! -x "$generation/activate" ]; then
  mkdir -p "$(dirname "$generation")"
  nix build "$flake" --out-link "$generation"
  "$generation/activate"
fi
