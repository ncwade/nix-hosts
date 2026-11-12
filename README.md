# nix-hosts

Private machine configuration assembled from:

- [nix-dotfiles](https://github.com/ncwade/nix-dotfiles): Home Manager profiles, user programs, skills, and wiki integration.
- [nix-config-defense-unicorns](https://github.com/ncwade/nix-config-defense-unicorns): employer host definitions and Git identity rules.

This repository owns NixOS, nix-darwin, system preferences, Homebrew, per-machine accounts, and provisioning. Both private Git inputs select `main` and are pinned to exact commits in `flake.lock`; access to them is required for a fresh evaluation of configurations that use them.

## Tycho personal server

`nixosConfigurations.tycho` manages the Framework Desktop (Ryzen AI Max+ 395,
64 GB RAM, 1 TB NVMe). It includes Tailscale and an Audiobookshelf service backed
by a TrueNAS NFS export. The library stays disabled until the export is configured.

Build its dedicated USB installer on this Mac using the existing Docker Desktop
Linux environment (avoids case-sensitivity problems in the Mac's Nix store):

```console
bash scripts/build-tycho-iso-docker.sh
```

Flash `artifacts/tycho/tycho-installer-x86_64.iso` to USB and boot with Ethernet
connected. The live environment accepts Luna's 1Password SSH key at
`nixos@tycho-installer.local`. From Luna, start installation with:

```console
ssh -t nixos@tycho-installer.local 'sudo tmux new-session -A -s tycho-install install-tycho'
```

It asks you to choose and confirm erasing the NVMe, installs the bundled system,
and prompts for your account password. After shutdown, remove the USB and power
on, then connect to `ncwade@tycho.local`. Secure Boot must already be disabled;
firmware changes can still require a temporary display. See the [installation and setup guide](docs/tycho.md)
for tailnet enrollment, TrueNAS activation, backups, and rebuilds.

## nas1 NAS migration

`nixosConfigurations.nas1` runs the NAS on its existing 16 GB boot device.
The five data drives are preserved, and only `/mnt/Data/documents` is mounted
and shared at `smb://nas1/docs`. The existing rsync.net backup runs daily at
midnight Central. See the [migration and recovery guide](docs/nas1.md) for
preservation checks, operation, and recovery.

## Use

```console
nix flake check --no-build --all-systems
nix build '.#darwinConfigurations.luna.system'
sudo darwin-rebuild switch --flake .#luna
```

Employer host names come from the private employer flake. The `homeConfigurations.mvm` output assembles the VM user profile; `scripts/mvm-home-manager.sh` targets this checkout at `~/src/github.com/ncwade/nix-hosts`.

Personal-wiki support is enabled only on `luna`. See the [wiki documentation in nix-dotfiles](https://github.com/ncwade/nix-dotfiles/blob/main/docs/personal-wiki.md).

## Update user configuration

Keep the checkouts side by side. Validate local edits without updating the published pin:

```console
nix flake check --no-build --all-systems --no-write-lock-file \
  --override-input nix-dotfiles path:../nix-dotfiles
```

After publishing the user-config changes:

```console
nix flake update nix-dotfiles
nix flake check --no-build --all-systems
```

Commit the updated lock file. Roll back a dependency update by restoring its previous lock-file revision. [Employer configuration](docs/employer-flakes.md) follows the same workflow.

## Migration and history

Machine-file history was extracted from the cleaned `ncwade/nix-config` branches as of `679e37ce806288f07c390ba6848e2a6f50ddf781`. Commits touching only user files were omitted; surviving commit IDs changed during extraction. Shared license/ignore history is retained in both new repositories.

Only cleaned branches were migrated. Old pull-request references and editor checkpoints were not imported. Older revisions are historical records and may refer to files that now belong in `nix-dotfiles`.

The original `nix-config` repository is retained; this migration does not purge GitHub-held references in that repository. Use this checkout for future machine changes. No host configuration was activated as part of the migration.
