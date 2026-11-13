# BookOrbit and tsidp on Tycho

This configuration replaces the unactivated Audiobookshelf/NFS design. All live
files use Tycho's ext4 SSD. BookOrbit 3.8.0 and PostgreSQL 18/pgvector images are
pinned by digest; tsidp 0.0.15 comes from the existing nixpkgs lock.

## Deployment status (2026-11-12)

Both NixOS configurations are activated. BookOrbit is live at
`https://bookorbit.tailf3d82.ts.net`; `http://bookorbit` and the original Tycho
HTTPS address redirect there with paths and queries preserved. Its separate
Tailscale node is enrolled, and tsidp remains at `idp.tailf3d82.ts.net`
(`100.82.96.99`). The dedicated daemon sets both `--statedir` and `--state`:
the former is required for HTTPS certificate storage.

The post-migration NAS1 snapshot `ee2f50dd` passed a full data check, file restore
verification (including the new node state), and SQL restoration into an isolated
PostgreSQL cluster (173 application tables). All four services resumed after the
backup. Web and native PKCE login, authenticated API requests, refresh, and logout
passed again after that restart. The existing administrator, two libraries, and
single linked Tailscale identity were preserved. The libraries were empty at
that deployment; subsequent media imports are recorded below.

The recovery password is saved in the Private 1Password vault as **BookOrbit
backup recovery — Tycho**. No secret value is stored in this repository.
The first offsite replication is due at the existing midnight run; it has not
yet been observed. The nightly Tycho timer is scheduled for 02:00 Central.

The administrator is `ncwade` (`me@ncwade.com`); its local recovery password is in
Private as **BookOrbit — Tycho**. The enabled **Tailscale** provider explicitly
links `ncwade@github` to that administrator. Automatic account creation and
automatic username-based linking are disabled. Web and native redirect flows
passed PKCE sign-in, authenticated API access, refresh, and logout checks.

The enrolled IdP is user-owned. Its admin grant targets `100.82.96.99`, as shown
below. Its node key currently expires on 2027-05-11. Key expiry remains enabled
at the owner’s request; re-enroll before that date.

The initial Tycho activation exposed a bind-mount permission issue and rolled
back automatically. The PostgreSQL mount parent now permits traversal (0711),
while the database-owned `pgdata` child stays private (0700). The corrected
activation and live restore test passed.

## Storage and access

| Purpose | Tycho path |
| --- | --- |
| Ebooks and audiobooks | `/srv/books/{ebooks,audiobooks}` |
| Covers, imports, app state | `/var/lib/bookorbit/app` |
| PostgreSQL files | `/var/lib/bookorbit/postgres` |
| App secrets | `/var/lib/bookorbit/secrets` |
| tsidp state | `/var/lib/tsidp` (systemd may store it under `/var/lib/private`) |
| BookOrbit Tailscale identity | `/var/lib/bookorbit-tailnet` |
| Consistent backup staging | `/var/lib/bookorbit-backup/staging` |
| Backup encryption password and SSH key | `/var/lib/bookorbit-backup/secrets` |

The library owner is `bookorbit`, UID/GID 2000. The app runs as that identity,
with a read-only container root and writable `/data`, `/books`, and `/tmp`.
The app binds to `127.0.0.1:3000`; PostgreSQL binds to `127.0.0.1:5433`.
Host networking lets the app reach the tailnet's OIDC issuer through the host's
DNS and routing. Neither port is opened in the firewall.

A dedicated userspace Tailscale node publishes
`https://bookorbit.tailf3d82.ts.net`. Its HTTPS listener proxies to BookOrbit;
`http://bookorbit` redirects to the full HTTPS name through a loopback-only nginx
listener on port 3001. HTTPS is required for the browser's OIDC PKCE crypto API,
even though Tailscale already encrypts transport. Bare `https://bookorbit` cannot
use the public certificate for the full tailnet name.

The original `https://tycho.tailf3d82.ts.net` address redirects to the new address,
preserving paths and queries. Tycho's machine identity and Rex port 7297 remain
independent; future applications can have separate service identities. Neither
node uses Funnel. Both the Apple client and browser need tailnet connectivity
for server access. Downloads work offline according to the client's capabilities.

On first deployment, obtain the BookOrbit node enrollment URL from
`journalctl -u bookorbit-tailnet-serve` and sign in to Tailscale. The separate
daemon uses `/run/bookorbit-tailnet/tailscaled.sock`; use
`sudo tailscale --socket=/run/bookorbit-tailnet/tailscaled.sock status` to inspect
it. The machine's ordinary `tailscale status` manages Tycho instead.

## Deploy and provision

Build first with `bash scripts/check-bookorbit-docker.sh`. Copy the reviewed
source to each host's `/etc/nixos`, preserving a backup of its previous contents.
Use `nixos-rebuild build`, then `test`, then `switch` for the matching host.
Do not run either host's disk installer.

After deploying NAS1, it creates this repository directory inside the existing
exported and backed-up documents dataset:

```
/mnt/Data/documents/backups/tycho/bookorbit
```

After deploying Tycho, `bookorbit-secrets.service` generates missing secrets and
a dedicated SSH key once; it never replaces existing credentials. Provision the
**public** key from `/var/lib/bookorbit-backup/secrets/id_ed25519.pub` on NAS1 at
`/etc/ssh/tycho-bookorbit-backup.pub`, owned by root, mode 0644. Never copy the
private key to NAS1. This account accepts only a forced SFTP command, with shell,
forwarding, and password authentication disabled. Its existing offsite rsync
credentials remain root-only systemd credentials.

The NAS SSH key is pinned to Luna's existing `nas1` known-hosts entry. Verify it
against the NAS console before changing it. A changed key must fail closed.
The configured NAS address is `192.168.3.63`; reserve that DHCP lease.

On Tycho, save the backup encryption password from
`/var/lib/bookorbit-backup/secrets/password` in your password manager before
initializing the repository. This recovery copy must survive losing Tycho; the
password is intentionally not stored next to the encrypted backup on NAS1.
Run once:

```sh
sudo bookorbit-restic init
sudo systemctl start bookorbit-backup
sudo bookorbit-restic snapshots
```

A normal backup never initializes the repository automatically or replaces its
password. Connection, credential, and repository errors fail visibly in
`journalctl -u bookorbit-backup` and `systemctl --failed`.

Complete BookOrbit's initial administrator setup at its tailnet URL using the
bootstrap token stored at `/var/lib/bookorbit/secrets/bootstrap`. Read that token
locally in a secure administrator session; do not paste it into logs or chat.
Create libraries pointing to `/books/ebooks` and `/books/audiobooks`.

## tsidp enrollment and BookOrbit OIDC

`services.tsidp` runs independently with hostname `idp`, Funnel disabled, and
optional token exchange disabled. On first startup, obtain the enrollment URL
from `journalctl -u tsidp` and register this service node in the personal tailnet.
The deployed node is user-owned with an IP-scoped admin grant. Key expiry remains
enabled by choice; renew enrollment before expiry. Keep phones/tablets user-owned: tagged
client devices do not have a user identity for tsidp login.

Give `ncwade@github` access to the tsidp admin UI through a scoped tailnet grant;
merge this into the existing policy instead of replacing the policy:

```json
{
  "src": ["ncwade@github"],
  "dst": ["100.82.96.99"],
  "app": {"tailscale.com/cap/tsidp": [{"allow_admin_ui": true}]}
}
```

Allow HTTPS network access to the IdP for intended readers and Tycho's
server-side token exchange. Network grants and app
capability grants are separate. No broad dynamic-client-registration grant is
required when creating the client through the admin UI.

At `https://idp.tailf3d82.ts.net`, register BookOrbit with these exact redirects (retain the old web URL for rollback):

```
https://bookorbit.tailf3d82.ts.net/oauth2-callback
https://tycho.tailf3d82.ts.net/oauth2-callback
bookorbit://oauth2-callback
```

In BookOrbit Settings > OIDC / SSO add issuer `https://idp.tailf3d82.ts.net`, the
registered client ID/secret, and scopes `openid profile email`. The module enables
`OIDC_ALLOW_LOCAL_ISSUERS=true` and retains TLS certificate verification. Use Test
and Preview Claims. Map the username claim to `username`, which resolves to
`ncwade`; GitHub-backed
Tailscale identities can have a synthetic email, so do not use it for mail delivery.
Link the existing administrator explicitly from account settings. Leave automatic
account creation off initially and retain the local recovery login. The provider
configuration and account links are database state included in backups.

Live protocol tests cover web and native redirects, PKCE, token exchange and
session renewal. The actual Safari and iOS app interfaces still require a device
acceptance check. Choose **Tailscale** on the BookOrbit login page, with Tailscale
connected on the device.

## Nightly backup and offsite replication

At **02:00 America/Chicago**, the systemd timer runs the backup job. Missed jobs
run after boot (`Persistent=true`). It pre-copies books and app files locally,
briefly stops BookOrbit, tsidp, and the dedicated BookOrbit tailnet services for
a final copy and `pg_dumpall`, then resumes
previously active services **before** contacting NAS1. A cleanup hook also resumes
them after a backup error or interruption. PostgreSQL stays running for the dump;
its raw live data directory is excluded. Do not modify library files externally
during the consistent-copy interval.

The staging tree includes books, app data, a logical database dump including roles,
app secrets, tsidp state, BookOrbit tailnet identity state, image/version metadata,
and backup connection settings.
It requires space for roughly one additional copy of the library and app data on
Tycho; check free space before large imports. It is root-only and contains secrets.

Restic encrypts and deduplicates the backup over SFTP. It verifies repository
structure, then retains 7 daily, 4 weekly, and 6 monthly snapshots. A success
marker is written only after backup, check, and retention all succeed.

NAS1's existing rsync job still runs at **midnight America/Chicago**, with the
same destination and deletion policy. Because the repository lives under
`documents`, the next midnight run includes the preceding 02:00 backup. The forced
SFTP receiver and the rsync job use the same exclusive lock. Incoming repository
operations and offsite copying cannot run concurrently. Each file is encrypted
before it reaches NAS1 or rsync.net. A NAS/network outage fails the backup without
holding BookOrbit or tsidp offline.

```sh
systemctl list-timers bookorbit-backup.timer
journalctl -u bookorbit-backup
sudo bookorbit-restic snapshots
sudo bookorbit-restic check --read-data
sudo cat /var/lib/bookorbit-backup/last-success
# On NAS1:
systemctl list-timers nas1-documents-backup.timer
journalctl -u nas1-documents-backup
```

Do not run rsync directly around the service lock. An interrupted offsite mirror
may be incomplete until the next successful run; the authoritative encrypted
repository remains on NAS1. Preserve independent rsync.net snapshots if available.

## Restore and rollback

Stop `bookorbit-audible.timer` and `bookorbit-audible.service` before restoring
media or Libation state. When the snapshot contains `libation`, restore it to
`/var/lib/libation`, owned by `bookorbit:bookorbit`, directory mode 0700 and
file mode 0600. It includes the account tokens, portable encryption key, SQLite
database, settings, and inventory. Start the timer only after verifying the
restored library. Snapshots predating the Audible importer require provisioning
the account again.

Also stop `bookorbit-kindle-sync.timer`, `bookorbit-kindle-sync.service`,
`bookorbit-kindle.timer`, and `bookorbit-kindle.service` before restoring books.
Restore the snapshot's `kindle/` directory to `/var/lib/bookorbit-kindle`, owned
by root, with 0700 directories and 0600 files. This includes its device credentials,
inventory, original downloads, conversion configuration, and completion hashes.
Restore it together with the books and `.kindle-import` receipts from the same
snapshot. Restart the timers only after validation. See [Kindle automation](kindle-import.md)
for partial-run diagnostics and authentication limitations.

Test restoration into separate directories and an isolated PostgreSQL container
before replacing production data. Retrieve the restic password from your password
manager and restore the desired snapshot with `bookorbit-restic restore` (or an
independent restic client pointing at the NAS/offsite repository). Run a full
`restic check --read-data` periodically; a structural check alone does not read
all stored book content.

On Tycho, `sudo bash /etc/nixos/scripts/check-bookorbit-restore.sh` performs a full
repository data check, restores the latest snapshot into a private temporary
directory, verifies its files, and imports SQL into an isolated PostgreSQL
container. It removes only its temporary restore data and container afterward.

1. Stop BookOrbit, tsidp, `bookorbit-tailnet-serve`, and `bookorbit-tailnet`; retain
   the existing live data for rollback.
2. Restore `books` to `/srv/books`, `app` to `/var/lib/bookorbit/app`, and `secrets`
   to `/var/lib/bookorbit/secrets`. Set book/app ownership to 2000:2000; app secrets
   are root:bookorbit, mode 0440, inside a 0750 directory.
3. Restore `postgres.sql` into a **fresh PostgreSQL cluster** using the saved image
   digest and installed extensions. Initialize it with a temporary administrator
   other than `bookorbit` so the dump can recreate the original role. Review every
   restore error before starting the app; never copy raw live database files.
4. Restore tsidp state while stopped, preserving systemd's StateDirectory ownership.
   Restore `tailnet` to `/var/lib/bookorbit-tailnet` (root-owned, directory 0700)
   while both dedicated tailnet services are stopped. Do not run two machines
   with the same restored identity. Older snapshots without `tailnet` need new
   enrollment. If moving machines, validate node identities and issuer URL.
5. Start PostgreSQL, BookOrbit, tsidp, `bookorbit-tailnet`, and
   `bookorbit-tailnet-serve`; verify OIDC, a book's contents, annotations,
   and listening/reading progress. Test offline-download reconciliation in iOS.

For this address migration, the previous NixOS generation retains the original
Tycho URL. The old OIDC callback remains registered, so generation rollback can
restore the prior address without altering accounts or libraries. Keep the new
node state even if rolling back; removing it would require enrollment again.

A NixOS generation rollback changes binaries and configuration, not database
migrations. Before updating image digests, complete a backup. Restore matching
application data and SQL when rolling back an incompatible schema change.

References: [BookOrbit installation and database recovery](https://bookorbit.app/installation/),
[BookOrbit OIDC](https://bookorbit.app/oidc/),
[tsidp](https://github.com/tailscale/tsidp),
[restic SFTP repositories](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#sftp).

## Unattended Audible imports

For automated Kindle library acquisition, native ebook formats, the manual
export inbox, and current rollout status, see [Kindle library imports](kindle-import.md).

Live acceptance on 2026-11-13: Libation reports **73 of 73 titles Liberated**,
and BookOrbit has **73 present audiobook records**, totaling **48.98 GiB** of
audio. The first successful server batches completed at **14:27:36 UTC** and
**14:37:27 UTC**. NAS1 backups completed after the initial 50 titles and again
after all 73 titles. Snapshot `52df89c0` passed the full encrypted-repository
data check (2,869 packs), restoration and verification of 445 files, and SQL
loading into an isolated PostgreSQL instance with 173 application tables.
The hourly import timer and five-minute BookOrbit
full scans remain enabled, with no daily download cap.

Tycho's `personal.bookorbit.audible.enable` adds `bookorbit-audible.timer`.
The hourly job (with up to five minutes of jitter and catch-up after boot) runs
Libation 14.2.5 in a digest-pinned container. It scans the configured Audible
accounts, reconciles downloaded status against existing files, then downloads
missing purchased audiobooks and companion PDFs. It does not mirror removals
from the storefront, overwrite existing recordings, or synchronize listening
progress with Audible. Podcasts and Plus subscription titles are excluded.

The job needs no laptop, browser, SSH connection, or BookOrbit API key. Account
reauthentication may still be required by Audible; failures are visible in the
systemd journal. Keep only one active downloader for an account. The Mac app can
remain installed for interactive management, but the server database is the
authoritative download history after migration.

State and credentials live in `/var/lib/libation` (0700, UID/GID 2000). Copy a
consistent desktop `LibationContext.db`, `AccountsSettings.json`, and the key
produced by `libationcli export-master-key` there through an encrypted connection.
Never put these files in this repository or the Nix store. The service is skipped
until the account file and key exist. Runtime settings are generated from
`modules/nixos/bookorbit/audible.nix`; edit that configuration rather than the
runtime `Settings.json`.

Finished AAC-LC M4B files go into `/srv/books/audiobooks`, one folder per title
with the Audible ID in the filename. Temporary downloads use
`/srv/books/.libation-in-progress`, outside both watched libraries. Both paths
share one container mount so completed audio can be renamed atomically.
BookOrbit's Audiobooks library uses Folder as Book, with watching disabled and
an auto-scan schedule of `*/5 * * * *`. Version 3.8.0's live watcher created both
folder and file records for incoming audio; full scans correctly reconcile one
book per folder. Scheduled scans avoid that duplicate-record path. M4B precedes
PDF in this library's format priority so companion documents do not replace the
audio as the primary file. These settings live in BookOrbit's backed-up database.
Leave file renaming disabled, or preserve Audible IDs so Libation can recognize
the files. For previously renamed audio, migrate `FileLocationsV2.json` with
verified container paths under `/books`; the two browser pilot uploads use this
cache because their filenames no longer contain the Audible ID.

There is no daily download cap. Each run downloads approximately 20 GB at most,
one title at a time. The next scheduled run resumes unfinished work. A disk-space check reserves
room for another audiobook-library copy plus 50 GiB; the service refuses to
download if that reserve would be exhausted. `/run/lock/bookorbit-media.lock`
serializes the downloader with the local backup snapshot; network backup runs
after releasing that lock. Temporary downloads are excluded from backups.

```sh
systemctl list-timers bookorbit-audible.timer
systemctl status bookorbit-audible.service
journalctl -u bookorbit-audible.service
sudo systemctl start bookorbit-audible.service
sudo cat /var/lib/libation/last-success
```

`last-success` records a completed CLI run with verified per-title results.
The 20 GB run bound can leave work for the next run; other incomplete owned
titles or companion PDFs fail the result check even when Libation exits zero.
`/var/lib/libation/inventory.json` records per-title download status, and
`/var/lib/libation/last-download.log` retains the latest download output privately.
For manual CLI maintenance, stop the timer/service first and hold the media lock:
`sudo flock /run/lock/bookorbit-media.lock bookorbit-audible-cli list-accounts`.
Do not run a second CLI container concurrently. Disable the timer to stop future
imports; downloaded files and BookOrbit reading state remain intact.

References: [Libation container setup](https://getlibation.com/docs/installation/docker),
[Libation CLI and encrypted-token portability](https://getlibation.com/docs/advanced/command-line-interface).

## Connector notifications

Tycho hosts ntfy at `https://tycho.tailf3d82.ts.net:8443`, through Tailscale Serve.
Its listener is loopback-only (`127.0.0.1:2586`); no public firewall port or
Funnel is enabled. Anonymous access is denied. Topic `bookorbit` has a dedicated
write-only `bookorbit-publisher` account and read-only `ncwade` account. Runtime
credentials and password hashes are created once under
`/var/lib/bookorbit-alerts` (root-only), never in the Nix store or this repository.

Install the ntfy iOS app, add this server and the `ncwade` user in Settings,
then subscribe to `bookorbit` on that server. Retrieve the reader password from
`credentials.json` through an administrator session. Keep Tailscale connected
on the phone. The configured `https://ntfy.sh` upstream sends only a wake-up
request with a message identifier and topic-URL hash; the phone fetches the
actual message from Tycho. On 2026-11-13 the user confirmed receipt of both fresh
failure and recovery test notifications while the iPhone app was backgrounded
or the phone was locked. Authentication remained enabled; a proposed
anonymous-access change was discarded before activation.

`bookorbit-alert-check.timer` checks every minute, and connector `OnFailure`
hooks trigger an immediate check. Audible scan/auth/download failures and
Kindle acquisition and manual-file import failures open separate incidents. Repeated failures are
suppressed. Recovery requires a new completed successful run; Kindle's ordinary
lock deferral cannot clear an incident. Notification failures retain queued
events for retry. An interruption after ntfy accepts a message but before local
state is saved can duplicate that message (at-least-once delivery).

Alerts contain only generic connector status; detailed errors stay in the
service journal and private connector logs. This monitors Audible acquisition,
Kindle library acquisition, and manual Kindle file imports separately. Kindle
scans all library categories; expired loans or other Amazon denials remain
reported failures. After the native-format update, acquisition resumed at
14:00 CST with its hourly timer active. A snapshot of 53 completed ledger items
passed independent hash, receipt, EPUB-spine, and native-format checks. The
273-item first pass is still running, so complete-library success is not yet proven. There is no Bookshop connector. A same-host notifier cannot report a total Tycho
or network outage while that outage is occurring.

```sh
systemctl status ntfy-sh bookorbit-alert-serve bookorbit-alert-check.timer
journalctl -u bookorbit-audible -u bookorbit-kindle-sync -u bookorbit-kindle -u bookorbit-alert-check
sudo bookorbit-alert-check --test-event failure
sudo bookorbit-alert-check --test-event recovery
```

The encrypted BookOrbit backup includes notification credentials, pending events,
incident state and connector success markers. Restore `staging/alerts` to
`/var/lib/bookorbit-alerts` and `staging/connector-health` to
`/var/lib/bookorbit-connector-health`, with mode 0700 directories, before starting
ntfy and the monitor. Provisioned users/ACLs are recreated on startup. The
seven-day ntfy message cache is disposable and is not included in backups.

Acceptance on 2026-11-13: Nix assertions and system build passed; focused tests
cover deduplication, recovery, lock deferral, pending-event retry, missing
credentials and Audible partial failures. Live checks confirmed anonymous
reads are denied, reader/publisher permissions are separated, and a temporary
invalid Kindle export generates exactly one failure and one subsequent recovery.
The test export was removed and the normal importer timer restored.
