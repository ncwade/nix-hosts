# nas1 TrueNAS to NixOS migration

`nixosConfigurations.nas1` runs the NAS on NixOS 26.11 with Linux 6.18.62
and OpenZFS 2.4.4. Installation replaced only the existing 16 GB boot device.
The documents share and daily backup are active and passed a subsequent reboot
check with no failed services.

Connect over SSH as `ncwade@192.168.3.63` and use `sudo` for administration,
or open `smb://192.168.3.63/docs`
using the existing `docs` login. The hostname remains `nas1`; use the IP if
your client has not refreshed its DNS registration. DHCP assigned `192.168.3.63` after installation; the previous
TrueNAS address was `192.168.3.62`. The original SSH server identity and permanent authorized login key are retained.
The permanent SSH key was verified with a successful login during Rex setup.
Temporary migration access was removed after verification.

Only `/mnt/Data/documents` is mounted and shared. All other datasets remain
intact and unmounted. Never add the existing data disks or pool to disko.

## Preservation and service checks

- Full SHA-256 comparison passed for all 7,679 files and 21,815,684,927 bytes.
- All 7,791 entries retained their ownership, modes, and modification timestamps;
  all 669 user extended attributes matched, including Mac metadata.
- UID 1001 (`docs`) could traverse and read every file.
- Authenticated SMB read and temporary write/read/delete checks passed.
- An actual file restored from rsync.net matched its original SHA-256 checksum.
- The NixOS backup service succeeded on November 11 at 17:14 Central with zero
  created, deleted, or transferred files. Its next run is midnight Central.
- The pre-migration snapshot is `Data/documents@before-nixos-20261111`.
- The data pool is healthy, with no forced imports or pool feature upgrades.
- A subsequent reboot restored the documents-only mount, SMB share, and backup
  timer automatically; no services failed.

Verification records are in the private, ignored `artifacts/nas1/` directory.

## Verified inventory on 2026-11-11

| Item | Observed value |
| --- | --- |
| OS | TrueNAS SCALE 24.10.0.2, Linux 6.6.44, ZFS 2.2.99 |
| Hardware | Intel Atom C3558, approximately 16 GiB RAM, UEFI |
| SSH before migration | `root@nas1`, `192.168.3.62` |
| Management interface | IPMI at `192.168.3.134`; user confirmed console/IPMI access |
| Active NIC | `enp4s0f1`, MAC `d0:50:99:fb:10:13`, DHCP |
| Boot device | 16GB SATA Flash Drive, serial `E02214117000000042BA`, 16,013,942,784 bytes |
| Boot device identity | `/dev/disk/by-id/ata-16GB_SATA_Flash_Drive_E02214117000000042BA` |
| Data pool | `Data`, GUID `3134546306779774706`, one five-disk RAIDZ2 vdev |
| Data drives | Four 4 TB drives and one 8 TB drive; all ONLINE with zero reported errors |
| Last recorded data scrub | 2026-04-26, zero errors |
| Documents | 7,679 regular files, 112 directories, 21,815,684,927 logical file bytes |
| Ownership | Documents and all inventoried files owned by `docs`, UID/GID 1001 |
| Encryption | `Data/documents` is unencrypted |
| SMB share | `docs`, currently `/mnt/Data/documents` |

The documents contain roughly 17 GiB of photos, 2.2 GiB of financial records,
1.2 GiB of books, 61 MiB of household records, and 34 MiB of reference material.
These directory sizes are rounded allocated-space measurements.

Other datasets include Time Machine backups, media, old application data, and
TrueNAS system data. They remain outside the required migration scope and must
not be formatted or deleted.

## Backup and permissions

TrueNAS rsync task 1 pushes `/mnt/Data/documents` to
`3451@usw-s003.rsync.net:truenas/`, resulting in the remote `truenas/documents`
directory. It is enabled daily at midnight America/Chicago. Job 77 reported
SUCCESS on November 11, 2026, from 15:21:35 to 15:21:46 Central.

A subsequent read-only `rsync -rtnc --itemize-changes --stats` comparison passed
with exit code 0, matching all 7,679 regular files and 21,815,684,927 bytes by
checksum. No files required creation or transfer, and there were no itemized
changes. This checks source-file coverage; it does not assert that the remote
directory contains no additional files, and it is not a full restore test.

The task copies files recursively and preserves timestamps, but does not
preserve owner/group, permissions, or extended attributes. It also propagates
deletions. A successful task alone is not proof of a complete restore.

Private recovery artifacts are in the ignored `artifacts/nas1/recovery/`:

- `truenas-config.tar`: official configuration export including the secret seed
  and root authorized public keys. Its SQLite database passed an integrity check.
- `documents-metadata.json.gz`: all inventoried file/directory paths, ownership,
  modes, timestamps, and base64-encoded extended attributes, plus dataset properties.
- `documents-checksums.json.gz`: SHA-256 manifest for all 7,679 regular files,
  taken from the frozen pre-migration snapshot.
- `docs.smbpasswd` and `service-credentials.tar`: private SMB login verifier,
  original SSH server keys, and existing backup SSH credentials.
- `SHA256SUMS`: checksums of the initial configuration and metadata archives.
- `TrueNAS-SCALE-24.10.0.2.iso`: recovery installer from the official download
  archive, verified against its published SHA-256 checksum. Its verification
  record and published checksum are stored beside it.

These contain sensitive information. Keep them outside source control and retain
them until both NixOS operation and recovery have been verified. The metadata
archive does not contain file contents and is not a standalone data backup.

`Data/documents` has `acltype=nfsv4`. Ordinary OpenZFS on Linux does not enforce
these ACLs as TrueNAS does; see the [OpenZFS ACL documentation](https://openzfs.github.io/openzfs-docs/Basic%20Concepts/Datasets/ACLs.html).
Five ACL representations were found, all using owner/group/everyone rather than
named-user rules. There are also Mac metadata streams. Keep UID/GID 1001 and
validate access as the `docs` account before enabling SMB. Do not recursively
change ownership, permissions, ACL type, or extended attributes as an import fix.

## Installation approach

Build and package locally, without connecting to the NAS:

```console
bash scripts/build-nas1-docker.sh
```

This reuses the existing Docker Linux build cache and writes the system and
disk-installer paths, evaluated safety checks, and a portable Nix package cache
under `artifacts/nas1/`. It does not perform an installation.

Use a pinned [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
to boot a temporary installer in RAM, then run only the reviewed boot-disk
partitioning and NixOS installation. The RAM-installer boot, disk identity checks, read-only pool import, and
boot-device installation all completed successfully.

The reviewed tool revision is `58132e1d1f813b845382a2aeca4203b18d2ac807`.
Retain the installation SSH credentials across separate phases and verify the
temporary installer's identity through the console. Preserve or explicitly
verify the final server SSH host key; do not blindly remove host-key checks.

The disk layout is in [disk-config.nix](../hosts/nas1/disk-config.nix): a 1 GiB
EFI partition and ext4 root on the identified flash device. No data drives or
ZFS pools are declared in disko. The built first-boot system occupies about
2.14 GiB before filesystem overhead. Three boot-menu generations and bounded
journal storage limit use of the small device.

The existing root public SSH key is configured. DHCP matches the observed NIC
MAC address. Forced imports are disabled. After verification,
`personal.nas1.documents.enable = true` activates the service that imports the
existing pool by GUID with `altroot=/mnt` and mounts only `Data/documents`.
This retains TrueNAS’s temporary mount prefix without changing stored dataset
mountpoints. Do not add the existing `Data` pool to disko.

## Completed cutover procedure

1. Finish the read-only rsync checksum comparison with exit code 0 and no missing
   or changed regular files. If there are differences, resolve them and repeat
   the comparison before replacing the OS.
2. Verify the IPMI console is usable and stage a verified TrueNAS 24.10.0.2
   recovery installer. Confirm the local recovery files are readable.
3. Arrange downtime, stop SMB/NFS and other writers, and complete a final backup
   check. Save a ZFS snapshot of the documents and refresh recovery metadata if
   anything changed. A snapshot on the same pool is not an off-box backup.
4. Cleanly export `Data`. TrueNAS's system dataset resides on this pool, so first
   account for its open files and middleware services; do not force an export
   just because it is busy. A normal shutdown into a recovery installer is the
   fallback if a clean export cannot be arranged with the RAM boot path.
5. Run only the `kexec` phase first. Confirm the temporary installer is reachable,
   all five data disks are present, no pool is imported, and the boot disk still
   matches both the serial and exact byte size above.
6. Before the destructive disk phase, approve replacing **only** the identified
   16 GB boot device. Recheck the generated disko script and its target. Never
   substitute an unstable name such as `/dev/sda`.
7. Install the prebuilt system and reboot. Confirm SSH, networking, disk space,
   and ZFS module availability before importing any pool.

The user authorized the boot-device replacement, and this procedure completed
on November 11, 2026. The initial bootstrap left the pool unimported; the final
configuration enables the verified documents service.

## First import and completion

After a clean export on TrueNAS, inspect available pools, then import the verified
GUID without mounting datasets and without writing to the pool:

```console
zpool import
zpool import -N -o readonly=on -o cachefile=none -R /mnt/nas1-readonly 3134546306779774706
zpool status Data
zfs mount Data/documents
```

The alternate root places the documents at
`/mnt/nas1-readonly/Data/documents`. Verify file counts and contents against
the backup and verify traversal/read access as UID 1001. Stop on import errors,
missing disks, checksum differences, or permissions problems. Do not use force,
rewind, recovery, or pool-upgrade flags to bypass a failure.

The final configuration restores the `docs` share with `fruit streams_xattr`,
imports the existing SMB password verifier into Samba’s private database, and
runs the backup as `nas-backup` (UID 1002, supplementary `docs` group). Its SSH
credentials are root-owned under `/var/lib/nas1-backup` and provided to the
service through systemd credentials, never through the Nix store.

Useful operational commands:

```console
systemctl status nas1-documents samba-smbd
systemctl start nas1-documents-backup
journalctl -u nas1-documents-backup
systemctl list-timers nas1-documents-backup.timer
zpool status Data
```

The scheduled backup retains the original deletion policy and runs at midnight
America/Chicago. It is a mirror, not a versioned backup, and does not preserve
Unix ownership, modes, or extended attributes. The private recovery metadata
archive supplements it. Retain that archive and the pre-migration snapshot.

Repository source is also staged at `/etc/nixos` on the NAS. Rebuilds should use
this flake; the explicit Docker build script can prepare Linux outputs locally.
The disk installation script is destructive and is not needed for rebuilds.

## Rex remote terminals

`hosts/nas1/rex.nix` enables the official Rex login server, pinned to
`0.1.0-preview.12` to match Tycho and Luna. The server is installed, running,
and enabled at boot. Its verified endpoint is
`https://nas1.tailf3d82.ts.net:7297`, available only through Tailscale.
The NAS has tailnet IPv4 address `100.87.210.43`.

Remote identity verification from Luna returned `ncwade@github` mapped to
`ncwade`. A temporary Rex terminal confirmed its account and hostname, exited
successfully, and was removed after the test.

Only Tailscale identity `ncwade@github` maps to the local `ncwade` account.
Terminals run as that account; anonymous access and remote root accounts are
disabled. The account also accepts the existing public SSH key. Its local password
was set and password-based sudo verified on 2026-11-13. Direct root SSH login is
disabled with `PermitRootLogin = "no"`; connect as `ncwade` and use `sudo` for
administration. No passwordless sudo rule is installed.

Tailscale Serve publishes the private Rex socket on HTTPS port 7297. The NAS
keeps its existing DNS configuration with `--accept-dns=false`. Enrollment
persists in `/var/lib/tailscale`.

```console
systemctl status rex-login-server rex-tailscale-serve
tailscale status
tailscale serve status
```

From a device on the tailnet, connect Rex to the endpoint above or verify it with:

```console
rex -S https://nas1.tailf3d82.ts.net:7297 whoami --json
```

In Rex for Mac, use **File > Add Remote Host…** with the same endpoint. The
command-line host entry did not appear in this app version's sidebar. Adding it
through the app opened a terminal showing `[ncwade@nas1:~]$` under
`nas1.tailf3d82.ts.net`.

## Rollback

The old boot environment is lost when the boot device is reformatted. Rollback
requires reinstalling the saved TrueNAS version on that same boot device,
restoring the configuration archive with its secret seed, and importing the
unchanged data pool. Keep the pool's feature set unchanged throughout the
compatibility window: do not run `zpool upgrade`. The TrueNAS installer must
never target one of the five data drives.

If NixOS has accepted new document writes, reconcile those writes and their
backup before reverting. An old snapshot is not an appropriate automatic
rollback target for newer user data.

## BookOrbit backup receiver

`hosts/nas1/bookorbit-backup.nix` creates
`/mnt/Data/documents/backups/tycho/bookorbit` for Tycho's encrypted restic repository.
It uses the existing documents dataset, so the unchanged midnight rsync scope
includes it automatically. Both rsync and incoming SFTP sessions take the same
exclusive lock to prevent copying a changing repository. The `nas-backup` account
accepts only forced SFTP for its dedicated Tycho key; provision that public key
at `/etc/ssh/tycho-bookorbit-backup.pub` (root-owned, 0644).

The 02:00 Tycho backup is copied offsite by the next midnight NAS1 run.
See [BookOrbit setup and recovery](bookorbit.md) for encryption-key escrow, initial
repository creation, retention, and restore verification.
