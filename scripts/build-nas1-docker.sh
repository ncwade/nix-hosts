#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output="$repo_root/artifacts/nas1"
mkdir -p "$output"
chmod 700 "$output"

# Build only. This script never connects to nas1 or executes the disk installer.
docker run --rm --name nas1-nixos-builder --platform linux/amd64 \
  --mount "type=bind,source=$repo_root,target=/checkout,readonly" \
  --mount "type=bind,source=$output,target=/output" \
  --mount type=volume,source=tycho-nix-build-cache,target=/nix \
  nixos/nix@sha256:f9823365cb4dbd4f1c056957d94e415b5bae73dfee33cf4da84c98a2f4ce9577 \
  sh -eu -c '
    mkdir /src
    for entry in flake.nix flake.lock hosts programs scripts installer docs README.md; do
      cp -R "/checkout/$entry" /src/
    done
    export NIX_CONFIG="experimental-features = nix-command flakes"
    nix eval --json path:/src#nixosConfigurations.nas1.config --apply '\''c:
      assert builtins.attrNames c.disko.devices.disk == [ "boot" ];
      assert c.disko.devices.disk.boot.device == "/dev/disk/by-id/ata-16GB_SATA_Flash_Drive_E02214117000000042BA";
      assert c.disko.devices.zpool == {};
      assert c.boot.zfs.extraPools == [];
      assert c.boot.zfs.forceImportAll == false;
      assert builtins.all (fs: fs.fsType != "zfs") (builtins.attrValues c.fileSystems);
      {
        bootDevice = c.disko.devices.disk.boot.device;
        zfsVersion = c.boot.zfs.package.version;
        automaticDataImport = c.personal.nas1.documents.enable;
        filesystems = builtins.attrNames c.fileSystems;
      }'\'' --no-write-lock-file > /output/evaluation-checks.json
    nas1_system=$(nix build path:/src#nixosConfigurations.nas1.config.system.build.toplevel \
      --no-write-lock-file --option sandbox false --option filter-syscalls false \
      --no-link --print-out-paths)
    nas1_disko=$(nix build path:/src#nixosConfigurations.nas1.config.system.build.diskoScript \
      --no-write-lock-file --option sandbox false --option filter-syscalls false \
      --no-link --print-out-paths)
    printf "%s\n" "$nas1_system" > /output/system-path.txt
    printf "%s\n" "$nas1_disko" > /output/disko-path.txt
    cp "$nas1_disko" /output/disko-reviewed.sh
    nix path-info --closure-size --json --json-format 1 "$nas1_system" > /output/system-size.json
    nix copy --to "file:///output/nix-cache?compression=zstd" "$nas1_system" "$nas1_disko"
  '

echo "Built system, disk installer, checks, and local package cache: $output"
