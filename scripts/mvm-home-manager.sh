#!/usr/bin/env bash
set -euo pipefail

# This script is invoked by mvm while it provisions its golden base. The Nix
# source below is a staged local Git flake, so keep this repository trusted.
flake='git+file:///Users/ncwade/src/github.com/ncwade/nix-config#homeConfigurations.mvm.activationPackage'
generation="$HOME/.local/state/mvm-home-manager/generation"

if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
fi

if ! command -v git >/dev/null 2>&1; then
  sudo apt-get -o DPkg::Lock::Timeout=300 update -qq
  sudo apt-get -o DPkg::Lock::Timeout=300 install -y git
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
