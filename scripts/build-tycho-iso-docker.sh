#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output="$repo_root/artifacts/tycho"
mkdir -p "$output"

# Official nixos/nix 2.34.9, pinned to its linux/amd64 manifest. Docker's
# Linux filesystem avoids case collisions in a macOS-hosted Nix store.
docker run --rm --name tycho-iso-builder --platform linux/amd64 \
  --mount "type=bind,source=$repo_root,target=/checkout,readonly" \
  --mount "type=bind,source=$output,target=/output" \
  --mount type=volume,source=tycho-nix-build-cache,target=/nix \
  nixos/nix@sha256:f9823365cb4dbd4f1c056957d94e415b5bae73dfee33cf4da84c98a2f4ce9577 \
  sh -eu -c '
    mkdir /src
    # Stage only source; never ingest .git or a previous ISO into the flake.
    for entry in flake.nix flake.lock modules hosts programs scripts installer docs README.md; do
      cp -R "/checkout/$entry" /src/
    done
    nix --extra-experimental-features "nix-command flakes" build \
      path:/src#packages.x86_64-linux.tycho-iso \
      --no-write-lock-file --option sandbox false --option filter-syscalls false \
      --print-build-logs \
      --out-link /tmp/tycho-iso
    cp /tmp/tycho-iso/iso/tycho-installer-x86_64.iso /output/
    cd /output
    sha256sum tycho-installer-x86_64.iso > tycho-installer-x86_64.iso.sha256
    chmod a+r tycho-installer-x86_64.iso tycho-installer-x86_64.iso.sha256
  '

echo "ISO and checksum: $output"
