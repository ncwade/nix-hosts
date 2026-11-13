# Tycho — Framework personal server

Tycho continues Luna's Red Rising naming theme. Hardware: Framework Desktop,
AMD Ryzen AI Max+ 395, 64 GB RAM, 1 TB NVMe. This host is personal and does not
import employer configuration or the macOS Home Manager profiles.

## Installed status — 2026-11-11

Installed and booted from the Samsung 970 EVO 1 TB NVMe with the USB removed.
Firmware is 03.06; the wired link negotiated 1 Gbps. SSH, Avahi, and Tailscale
are enabled and running, with no failed system services at verification.

- Personal tailnet: `ncwade.github`, shared with Luna.
- Tailscale name: `tycho.tailf3d82.ts.net`; IPv4: `100.107.121.58`.
- Remote administration: `ssh ncwade@tycho.tailf3d82.ts.net`.
- LAN recovery: `ssh ncwade@tycho.local` using Luna's 1Password key.
- Tailscale ping and an authenticated Tailscale SSH session from Luna passed.
  The SSH policy requested a browser identity check, which was completed.
- The initial installation left Audiobookshelf disabled. Its replacement is
  [BookOrbit with tsidp and local storage](bookorbit.md); deploy and provision it
  separately using that guide.

## What is prepared

- NixOS x86_64, UEFI/systemd-boot, current pinned kernel and AMD firmware.
- An unencrypted ext4 root and a 1 GiB EFI partition; zram supplies swap.
  Unencrypted storage permits unattended restarts. Decide before installing if
  local disk encryption is required; this installer does not set up LUKS.
- The `ncwade` administrator, key-only OpenSSH over the LAN, Tailscale SSH,
  firmware tooling, SSD trim, and disabled sleep/hibernation.
- BookOrbit for ebooks and audiobooks, with all live data on Tycho's SSD.
- tsidp for tailnet identity login; encrypted nightly backups to NAS1, then its
  regular offsite rsync. See [deployment and recovery](bookorbit.md).
- NAS1's existing SMB documents share mounts on demand at `/mnt/nas1/docs`,
  after provisioning the credential described below.

## NAS1 documents share

Activated on Tycho on 2026-11-12. The live CIFS mount and a temporary-file
write/read/delete check passed as `ncwade`. The credential is provisioned on
Tycho with mode `0600`, owned by `root:root`; its value is not in this repository.

`hosts/tycho/nas1.nix` mounts `//192.168.3.63/docs` at `/mnt/nas1/docs` using
SMB 3.1.1. This is NAS1's existing documents share; BookOrbit's `/srv/books`
library is local to Tycho. The address is NAS1's last verified LAN DHCP lease; reserve it in
the router or update the source if the lease changes.

The mount is read/write for `ncwade`, with local file/directory modes `0600` and
`0700`. NAS1 still checks access using its existing `docs` account. Accessing
the directory triggers the mount; it unmounts after five idle minutes. Boot
does not require NAS1 or a working credential, and mount attempts time out
after 30 seconds. Programs accessing the share can still wait or fail during
a network outage.

Provision the credential **on Tycho** before first access:

```sh
sudo install -d -m 0700 -o root -g root /var/lib/samba/credentials
sudo sh -c 'umask 077; touch /var/lib/samba/credentials/nas1-docs'
sudo chown root:root /var/lib/samba/credentials/nas1-docs
sudo chmod 0600 /var/lib/samba/credentials/nas1-docs
sudoedit /var/lib/samba/credentials/nas1-docs
```

Enter these two lines, replacing the placeholder with the existing SMB password:

```ini
username=docs
password=<existing docs password>
```

Do not put the credential in this checkout or use `environment.etc.*.text` for
it: that would copy the password into the Nix store. The runtime file survives
rebuilds but must be provisioned again on a fresh installation.

Sync the updated source to `/etc/nixos`, then activate and verify on Tycho:

```sh
sudo nixos-rebuild switch --flake path:/etc/nixos#tycho
systemctl status mnt-nas1-docs.automount
ls /mnt/nas1/docs
findmnt -t cifs --mountpoint /mnt/nas1/docs
```

Run `ls` as `ncwade` to check ordinary user access. After correcting a password
or restoring NAS1 connectivity, retry access; if the mount remains failed, run
`sudo systemctl reset-failed mnt-nas1-docs.mount` first. Inspect mount failures
with `journalctl -u mnt-nas1-docs.mount`.

Validate the repository configuration without connecting to either host:

```sh
nix eval --impure --json --expr 'let f = builtins.getFlake ("path:" + toString ./.); in import ./tests/tycho.nix { host = f.nixosConfigurations.tycho; installer = f.nixosConfigurations.tycho-installer; }'
```

## Build and flash the USB

From the nix-hosts checkout on this Mac, with Docker Desktop running:

```sh
bash scripts/build-tycho-iso-docker.sh
cd artifacts/tycho
shasum -a 256 -c tycho-installer-x86_64.iso.sha256
```

The script uses the official Nix 2.34.9 x86_64 container, pinned by digest, and a
task-specific `tycho-nix-build-cache` Docker volume. Source is mounted read-only;
only the ISO and checksum are written into `artifacts/tycho`. The volume keeps
downloaded dependencies for later builds; remove it with
`docker volume rm tycho-nix-build-cache` when no build is running if no longer needed.

Determinate Nix's [Native Linux Builder](https://docs.determinate.systems/determinate-nix/native-linux-builder/)
does support x86_64 Linux builds on Apple Silicon, and a test build succeeded on
this Mac. The full image hit its documented [case-sensitivity limitation](https://determinate.systems/blog/native-linux-builder-ga/#case-sensitivity-and-hash-mismatches):
the boot-image build could not find `ncurses` terminal definitions after Nix
renamed case-colliding directories in the Mac's store. Docker builds in its own
case-sensitive Linux filesystem, with no reinstall of the Mac's Nix installation.

On a native x86_64 Linux machine, or a Mac with a compatible case-sensitive Nix
store and Determinate builder, the direct build is:

```sh
nix build 'path:.#tycho-iso' --no-write-lock-file
```

That places the ISO at `result/iso/tycho-installer-x86_64.iso`. The first build
downloads Linux dependencies and can take a while.

Use balenaEtcher to flash `artifacts/tycho/tycho-installer-x86_64.iso` onto a USB drive
large enough for the image (16 GB recommended). Select the USB carefully; flashing
erases that USB. The ISO contains the target system and a configuration snapshot,
so installation does not require internet or access to private Git inputs.
Rebuild the ISO after changing the host configuration.

## Boot and install remotely from Luna

The USB boots into a live environment and waits. Booting alone never partitions
or erases the NVMe. Luna's existing 1Password public key is authorized for `nixos`
in the live environment and `ncwade` in the installed system. Its public half is
in `hosts/tycho/admin.pub`; no private key or password is included on the USB.
SSH password login, keyboard-interactive login, and remote root login are disabled.

1. Connect the Framework's Ethernet to the same home LAN as Luna. Insert the USB
   while powered off, then power on. A blank internal drive should boot the USB
   automatically. Secure Boot must already be disabled. If firmware blocks the
   USB or selects an existing OS instead, a temporary display/keyboard may be
   needed for F2 settings or the F12 boot menu. This cannot be fixed through SSH
   before the live system boots. See Framework's [NixOS installation guide](https://guides.frame.work/Guide/NixOS+on+the+Framework+Desktop/417).
2. Allow a few minutes to boot and obtain a DHCP address. Unlock 1Password on Luna,
   then connect:

   ```sh
   ssh nixos@tycho-installer.local
   ```

   Approve 1Password's key-use prompt if shown. The live system advertises its
   address with mDNS. If `.local` does not resolve, find `tycho-installer` in the
   router's DHCP lease list and use its IP address instead. Guest Wi-Fi/client
   isolation or separate VLANs can block discovery and SSH; use the same LAN.
3. Start installation in a persistent terminal from Luna:

   ```sh
   ssh -t nixos@tycho-installer.local 'sudo tmux new-session -A -s tycho-install install-tycho'
   ```

   The installer lists drive model, size, and serial. Enter the whole 1 TB NVMe
   device and type the exact erase confirmation. It refuses partitions,
   non-NVMe targets, and mounted disks. It creates `TYCHO-BOOT` and `tycho-root`,
   installs the bundled system, saves configuration to `/etc/nixos`, and records
   the hardware scan in `/etc/nixos/hardware-detected.nix`.
4. Set the `ncwade` password when prompted through SSH. This password is for sudo
   and optional console login; SSH continues to use the key. Press Enter to shut
   down. The SSH connection closing at shutdown is expected.
5. Remove the USB, power on, and reconnect from Luna:

   ```sh
   ssh ncwade@tycho.local
   ```

If the network disconnects during installation, reconnect with the same tmux
command to reattach to the running session. Do not launch a second installation.
If the installer itself fails and the session has ended, inspect the error and
mounted filesystems before retrying: starting `install-tycho` again starts the
erase workflow again. Do not use it to repair an existing installation.

The live environment generates new SSH host keys on each USB boot; the installed
system generates its own persistent host keys. Expect a new first-use host key
after installation. If reusing a hostname/IP and SSH reports a changed key,
confirm it is the freshly booted Framework before removing that specific stale
entry from Luna's `known_hosts`. Do not disable host-key checking globally.

The planned hardware module has not been scanned on the physical machine. Compare
the saved scan with `hosts/tycho/hardware.nix` after installation, and bring any
needed hardware changes back to this checkout. Keep the labels or use the scanned
UUIDs consistently. Leave `system.stateVersion` at its installation value.

## Join the tailnet

From Luna, connect with `ssh ncwade@tycho.local`, then run on Tycho:

```sh
sudo tailscale up --ssh
tailscale status
tailscale ip -4
```

Open the displayed login URL on a trusted device and choose the personal tailnet.
Approve the device if required. `--ssh` enables Tailscale SSH; ensure your tailnet
SSH policy allows your identity to access `ncwade` on Tycho. Then test from Luna:

```sh
ssh ncwade@tycho
```

With `--ssh` enabled, connections to port 22 on Tycho's Tailscale address use
Tailscale identity and its SSH policy; they may request a browser identity check.
Luna's 1Password key remains available for ordinary OpenSSH over the LAN. The
same public key is authorized in the live installer and installed system to
avoid a headless lockout. The administrator password is used for sudo.
See [Tailscale SSH behavior](https://tailscale.com/docs/features/tailscale-ssh).
LAN SSH stays enabled for recovery; once tailnet access is verified, it can be
restricted to the tailnet by setting `services.openssh.openFirewall = false` in
the host module. The existing `tailscale0` firewall rule keeps tailnet SSH open.

Use the Tailscale admin console to choose an appropriate device key-expiration
policy for an unattended server. Enrollment persists in `/var/lib/tailscale`.
The server advertises neither an exit node nor subnet routes. No router port
forwarding is needed. Tailnet policy should restrict SSH to the administrator
and HTTPS to the intended library users.

## BookOrbit, tsidp, and nightly backups

See [the BookOrbit guide](bookorbit.md) for local storage, runtime secrets,
tailnet HTTPS, OIDC setup, NAS1 backup provisioning, and restore procedures.
BookOrbit has its own `bookorbit.tailf3d82.ts.net` node. Tycho’s port 443 redirects
to it; Rex remains on Tycho’s port 7297. `http://bookorbit` is a shortcut to HTTPS.

## Rex remote terminals

`hosts/tycho/rex.nix` enables the official Rex NixOS login server, pinned to
`0.1.0-preview.12` to match Luna. Its private Unix socket is published by the
`rex-tailscale-serve` service at `https://tycho.tailf3d82.ts.net:7297`.
Only Tailscale identity `ncwade@github` maps to the local `ncwade` account.
Anonymous access and remote root accounts are disabled.

From Luna, verify access with:

```sh
rex -S https://tycho.tailf3d82.ts.net:7297 whoami --json
```

Luna's Rex app has a connected remote host named **Tycho**. To recreate it,
choose **Add Remote Host**, enter `https://tycho.tailf3d82.ts.net:7297`, and connect.
Right-click the host in the sidebar, choose **Edit Host**, set **Name** to
`Tycho`, and save. Rex stores this app preference locally on the Mac; it is not
part of the NixOS configuration.

The CLI host alias is separate from the app's sidebar entry. It is also configured
on Luna and can be recreated on another machine with:

```sh
rex hosts add Tycho https://tycho.tailf3d82.ts.net:7297
rex -S Tycho whoami --json
```

On Tycho, inspect `systemctl status rex-login-server rex-tailscale-serve` and
`tailscale serve status`. Rex's mapping uses port 7297 so the library's Serve
mapping on 443 can coexist. No application HTTPS firewall ports are opened.
The originally flashed USB predates Rex; rebuild the ISO to include it in a
fresh installation.

## Updates, backups, and verification

The USB installs a writable source snapshot at `/etc/nixos`. Keep this repository
as the source of truth; sync reviewed changes there before rebuilding. Source
evaluation of the personal server uses nixpkgs; the other flake outputs reference
private user/employer inputs, so full all-system checks need access to those inputs.

On Tycho:

```sh
sudo nixos-rebuild build --flake path:/etc/nixos#tycho
sudo nixos-rebuild test --flake path:/etc/nixos#tycho
# After verifying SSH, Tailscale, and (when enabled) the library:
sudo nixos-rebuild switch --flake path:/etc/nixos#tycho
```

For a failed system update, select a previous generation in the boot menu or use
`sudo nixos-rebuild switch --rollback`. A system rollback does not undo application
database changes. Follow the [BookOrbit recovery procedure](bookorbit.md#restore-and-rollback)
for a matching data restore. Never commit application secrets or Tailscale state.

Acceptance on the real machine includes reboot, tailnet SSH, ebook/audio playback,
persisted progress, Safari and iOS OIDC login, backup restoration, and reading while
NAS1 is unavailable. Ports 3000 and 5433 must not be reachable from the LAN.
