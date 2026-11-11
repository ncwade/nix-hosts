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
- TrueNAS storage and Audiobookshelf remain disabled pending the real export.

## What is prepared

- NixOS x86_64, UEFI/systemd-boot, current pinned kernel and AMD firmware.
- An unencrypted ext4 root and a 1 GiB EFI partition; zram supplies swap.
  Unencrypted storage permits unattended restarts. Decide before installing if
  local disk encryption is required; this installer does not set up LUKS.
- The `ncwade` administrator, key-only OpenSSH over the LAN, Tailscale SSH,
  firmware tooling, SSD trim, and disabled sleep/hibernation.
- Audiobookshelf for audiobooks and basic ebook reading. Media lives at
  `/srv/books` on TrueNAS; its database, metadata, and progress live locally at
  `/var/lib/audiobookshelf` and need a separate backup.
- TrueNAS is offline, so `personal.books.nfsSource = null` keeps the mount and
  application disabled. No NAS address, export, or tailnet credentials are invented.

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

## Activate TrueNAS and the library when the NAS is online

This configuration assumes **NFSv4.2 over the trusted LAN**. If the existing share
is SMB-only, update the mount for SMB before enabling it; do not paste an SMB path
into the NFS source. NAS storage does not depend on the tailnet.

1. Reserve Tycho's Ethernet IP in DHCP. On TrueNAS, create or select a books dataset,
   with `audiobooks` and `ebooks` subdirectories. Configure snapshots and a backup
   of that dataset; snapshots alone are not an independent backup.
2. Use a dedicated books owner. The host reserves UID/GID **2000:2000** for
   `audiobookshelf`. Match these IDs on TrueNAS or change both values in
   `hosts/tycho/default.nix` before first library activation. Grant this identity
   directory traversal and read/write access. Do not solve permissions with 777.
3. Export only this dataset through NFSv4.2, restrict Authorized Hosts to Tycho's
   reserved LAN address, and enable the NFS service at boot. If using Mapall, map
   to the dedicated books account, never root. See [TrueNAS NFS setup](https://www.truenas.com/docs/scale/shares/nfs/).
4. Set the actual source in `hosts/tycho/default.nix`, for example:

   ```nix
   personal.books.nfsSource = "192.168.1.10:/mnt/tank/books";
   ```

   That address and dataset are examples, not discovered values. Use the actual
   export reported by your NAS. Deploy the updated configuration as described below.
5. On Tycho, verify before creating any library:

   ```sh
   findmnt /srv/books
   sudo -u audiobookshelf test -r /srv/books/audiobooks
   sudo -u audiobookshelf test -w /srv/books/audiobooks
   sudo -u audiobookshelf test -r /srv/books/ebooks
   sudo -u audiobookshelf test -w /srv/books/ebooks
   systemctl status audiobookshelf
   curl --fail http://127.0.0.1:8000/ping
   ```

The application requires the NFS mount. If the NAS cannot mount, the server still
boots and remains manageable, but the application does not start. If the mount is
removed, the application stops. A mid-session NAS outage may stall reads because
the mount is `hard`; it will not silently fall back to local storage. Once the NAS
returns, reads resume. After an initial mount failure, recover with:

```sh
sudo systemctl reset-failed srv-books.mount audiobookshelf.service
sudo systemctl start audiobookshelf.service
```

## Publish the library inside the tailnet

All application access uses Tailscale Serve. Applications bind to localhost or
Unix sockets; they do not listen directly on LAN/public HTTPS ports. HTTPS ports
below belong to Tailscale Serve and are reachable only through the tailnet.

Audiobookshelf listens only on loopback. Before sharing it, create its administrator
account using an SSH tunnel from Luna:

```sh
ssh -L 8000:127.0.0.1:8000 ncwade@tycho
```

Open `http://localhost:8000`, set the administrator password, and create libraries
pointing to `/srv/books/audiobooks` and `/srv/books/ebooks`. Leave **Audiobooks only**
off for the ebook library. Audiobookshelf offers [basic ebook reading](https://audiobookshelf.org/docs/documentation/libraries/book-library/ebooks/);
dedicated ebook catalog/conversion workflows may need another service later.

On Tycho, publish HTTPS through [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve):

```sh
sudo tailscale serve --bg --https=443 http://127.0.0.1:8000
tailscale serve status
```

Enable MagicDNS/HTTPS in the personal tailnet if prompted. Use the exact HTTPS URL
shown by Serve for the browser and audiobook clients. Serve's background setting
persists across reboots. Do not use Funnel: this is a private tailnet service.
Keep Audiobookshelf accounts enabled for per-user progress and permissions.
Use scheduled library scans if changes made directly on NFS are not detected.

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
database changes. Keep a stopped-service backup of `/var/lib/audiobookshelf` before
updating it, in addition to TrueNAS media snapshots. For example, with the NAS mounted
and a writable `backups/tycho` directory provisioned on that dataset:

```sh
mountpoint /srv/books
sudo systemctl stop audiobookshelf
sudo -u audiobookshelf rsync -a /var/lib/audiobookshelf/ /srv/books/backups/tycho/audiobookshelf/
sudo systemctl start audiobookshelf
```

Snapshot/replicate that backup on TrueNAS; it contains accounts and listening
progress. Restore with Audiobookshelf stopped and restore its local ownership.
Test restoring a backup before relying on it. Tailscale state can be recovered by
re-enrollment; never commit it or authentication secrets to the repository.

Acceptance on the real machine: reboot without USB; verify NVMe/firmware/network
health, tailnet SSH, a book playback, an EPUB opening, persisted progress after
another reboot, and behavior while the NAS is unavailable. Confirm that port 8000
is not reachable directly from the LAN. Building the ISO alone does not prove
physical boot or access to the currently offline NAS.
