#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
docker run --rm --name bookorbit-nixos-check --platform linux/amd64 \
  --mount "type=bind,source=$repo_root,target=/checkout,readonly" \
  --mount type=volume,source=tycho-nix-build-cache,target=/nix \
  nixos/nix@sha256:f9823365cb4dbd4f1c056957d94e415b5bae73dfee33cf4da84c98a2f4ce9577 \
  sh -eu -c '
    mkdir /src
    for entry in flake.nix flake.lock modules hosts programs installer tests scripts; do
      cp -R "/checkout/$entry" /src/
    done
    export NIX_CONFIG="experimental-features = nix-command flakes"
    nix eval --impure --json --expr '\''let f = builtins.getFlake "path:/src"; in import /src/tests/bookorbit.nix { tycho = f.nixosConfigurations.tycho; nas1 = f.nixosConfigurations.nas1; }'\''
    nix eval --impure --json --expr '\''let f = builtins.getFlake "path:/src"; in import /src/tests/tycho.nix { host = f.nixosConfigurations.tycho; installer = f.nixosConfigurations.tycho-installer; }'\''
    nix build path:/src#nixosConfigurations.tycho.config.system.build.toplevel \
      path:/src#nixosConfigurations.nas1.config.system.build.toplevel \
      --no-write-lock-file --option sandbox false --option filter-syscalls false --no-link
  '
