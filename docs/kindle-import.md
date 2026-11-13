# Kindle library imports into BookOrbit

Tycho has two separate paths: `bookorbit-kindle-sync` downloads the complete
Amazon library inventory using saved device credentials, while
`bookorbit-kindle` imports completed files from the manual export inbox. Ordinary
server runs do not depend on the Mac staying open. Initial authentication and
some future authentication challenges still require the user.

## Deployment checkpoint — 2026-11-13

The user approved unofficial device registration and then expanded acquisition
to all library categories. The complete paginated inventory contains 273 items:
201 purchases, 20 Kindle Unlimited items, 11 library loans, 34 dictionaries,
3 rentals, 1 sample, and 3 personal documents. Inventory presence does not prove
Amazon will authorize a download. There is no purchase-only filter.

The first server batch imported 48 new items before a pause to preserve native
dictionary formats instead of spending minutes converting them to EPUB. The
native-format deployment passed and the batch resumed at **14:00 CST** with the
hourly acquisition timer active. A snapshot of **53 completed ledger items** was
independently checked against file hashes, importer receipts, EPUB spine data,
and native-format validation with zero errors. The complete 273-item pass is
still running; this snapshot is not a complete-library success claim.

Two public-library items returned HTTP 403; Amazon explicitly reported
**“loan has ended”** for the first. These are recorded failures, not successful
imports or proof of a general authentication failure. The Mac and Linux Fracture
pilots passed offline conversion and text comparison against its official export;
a later Linux run reported unchanged, preserving the existing BookOrbit copy.
The actual decrypted 43 MB Oxford dictionary passes native validation. All
**13 importer tests and 14 sync tests passed on Tycho**, including the real-qpdf
checks. The backup taken during the pause completed. Its Kindle credentials and ledger
were restored from encrypted NAS1 storage and matched byte-for-byte with private
permissions preserved. At the later iPhone delivery checkpoint, the completion
ledger contained 76 of 273 items; the batch remained active. Seven public-library
items had returned HTTP 403, and one purchased title remained encrypted after
all configured voucher candidates failed. These exceptions remain pending; the
initial pass has not completed. A fresh backup is queued behind that pass. Later batch and final
backup results must be recorded after they finish.

## Acquisition boundary checked on 2026-11-13

Amazon offers EPUB/PDF downloads for purchased books whose publishers enable
DRM-free export. Older DRM-free books may still need publisher opt-in. Borrowed
titles do not qualify. The exact account check is the
[Amazon Content Library](https://www.amazon.com/hz/mycd/myx#/home/content/booksAll/dateDsc/):
look for **Download available in additional formats**, then open **More actions →
Download EPUB/PDF**. Prefer EPUB for reflowable books; retain PDF when that is the
available export.
See [Amazon's official export rules](https://kdp.amazon.com/en_US/help/topic/GDDXGH9VR22ACM8U).

The account displayed 236 content entries, including borrowed titles and samples.
Eligibility and a successful official export were confirmed for the purchased
**Fracture (Galaxy's Edge: Legacies Book 10)**, ASIN **B0GRZR9S8P**. The full
official-export eligibility audit remains incomplete; bulk browser work was
paused in favor of the authorized headless acquisition path.

The browser saved the tested EPUB with a `.zip` filename, without opening a
confirmation dialog. Inspection confirmed `mimetype` was `application/epub+zip`,
with `META-INF/container.xml`, `OEBPS/opf.opf`, and XHTML content: this archive was
the EPUB itself, not an outer package containing a separate EPUB. Preserve the
download and copy its unchanged bytes to an `.epub` filename only after validating
that structure. Do not blindly rename arbitrary ZIP files or extract the book's
internal files for import. Browser automation must attach its download-event
listener before clicking the menu action; a closing menu alone does not mean the
export failed. This observed filename does not establish the packaging of every
Amazon export.

Official EPUB/PDF export and the device-protocol acquisition service are different
paths. The automated connector uses the reviewed `kindl` client, not an official
Amazon EPUB/PDF export API. Its success does not expand the official download
eligibility rules. Amazon passwords and browser cookies are not stored by this
connector; private device tokens, signing keys, and account secrets are retained
for unattended requests. See the runtime and operational sections below.

## Enable on Tycho

The BookOrbit module imports `kindle.nix` and `kindle-sync.nix`. Enable them with:

```nix
personal.bookorbit.kindle.enable = true;
```

The default uploader is the existing `ncwade` account. This adds no SSH key or
network port. Build and deploy through the existing BookOrbit deployment workflow.

Set the Ebooks library to **Folder as Book**, **Watch folders off**, a custom
auto-scan schedule of `*/5 * * * *`, and EPUB first in its format priority.
BookOrbit supports EPUB/PDF and native MOBI/AZW/AZW3; preserve the actual supported
file extension rather than renaming formats to change reader selection.
Keep file renaming and metadata write-back disabled. The live watcher produced
duplicate folder/file records during the audiobook migration on BookOrbit 3.8.0;
scheduled full scans use the reconciliation path verified there. The real
Fracture export passed the import and reading checks described below.

## Queue an export

The ASIN is the ten-character identifier on the purchased title's Amazon page.
Use the ASIN for that ebook edition, not an ISBN or an audiobook's ASIN.
If the browser saves a `.zip`, inspect its `mimetype` and EPUB structure first.
For a valid EPUB archive, copy the unchanged file to an `.epub` filename and pass
that copy to the helper. The helper accepts validated EPUB/PDF files, not generic
ZIP packages.

```sh
bash scripts/queue-kindle-book.sh B012345678 '/absolute/path/to/export.epub'
```

The helper copies over SSH to a unique `.part` file, then renames it to
`/srv/kindle-inbox/B012345678.epub` only after transfer finishes. It retains the
local source. A direct uploader must use the same atomic completion convention;
do not write an active upload directly to a final `.epub` or `.pdf` pathname.

| Location on Tycho | Purpose |
| --- | --- |
| `/srv/kindle-inbox/ASIN.epub` or `ASIN.pdf` | Completed exports; owner `ncwade`, private; source retained |
| `/srv/books/ebooks/Kindle [ID]/book.format` | Validated EPUB, PDF, MOBI, AZW, or AZW3; owner `bookorbit` |
| `/srv/books/.kindle-import/ASIN.format.json` | Import receipt and content hash, root-only |
| `/srv/books/.kindle-import/revisions/ASIN/hash.format` | Previous versions retained for recovery, root-only |

`bookorbit-kindle.timer` runs every five minutes and catches up after boot.
BookOrbit's separate five-minute library scan makes the book available, normally
within ten minutes after queuing. The automated acquisition job calls the same
importer directly after offline processing; it keeps its source packages in private acquisition state.

Files are checked before publication: EPUB archive/package integrity and content
encryption, or PDF structure/encryption using qpdf. Native MOBI/AZW/AZW3 checks
validate the PalmDB record table and bounds, PalmDOC encryption flag, text-record
bounds, MOBI/EXTH lengths, and linked KF8 headers in combined books. Both primary
and secondary headers must be unencrypted. This is structural validation, not a
full text decompression or rendering check. Recognized EPUB font obfuscation is
allowed. Native files are published with unchanged bytes after validation.
A same-content reimport leaves the current file untouched.
A changed export is published at the same stable path after saving and verifying
the prior version. If the destination was independently changed, the importer
fails rather than overwriting it. Changes in the book's text can still affect
saved reading locations; retaining a path does not guarantee position equivalence
between editions.

The importer shares `/run/lock/bookorbit-media.lock` with Audible and backups.
When the lock is busy, it logs a deferral and exits successfully; the next
five-minute timer retries without waiting behind a long audiobook batch.
No download/day cap is involved. Its space check reserves twice the incoming file
size plus 1 GiB as a per-import safeguard; capacity for the full backup staging
tree must still be provisioned separately. The existing `/srv/books` backup includes current
ebooks, receipts, and prior revisions. The inbox itself is not backed up; a file
that failed validation remains there and in its original local download location.
No ebook is removed when a source export or Amazon purchase disappears.

```sh
systemctl list-timers bookorbit-kindle
systemctl status bookorbit-kindle
journalctl -u bookorbit-kindle
sudo bookorbit-kindle-import
```

To pause future imports, stop `bookorbit-kindle.timer`. A failed export does not
prevent other queued titles from importing, but the batch reports failure in
systemd so it is visible. Replace the bad source with a fresh completed export.

For rollback, stop the importer timer, hold the shared media lock, restore the
desired archived revision to the stable library filename, and update the inbox
to that same revision before resuming. Keep the latest receipt or allow the next
identical import to repair it; an unrecognized differing destination fails closed.

## Validation

`python3 tests/bookorbit-kindle.py` exercises idempotence, revision preservation,
external-change conflict, encrypted/broken exports, symlinks, upload mutation,
interrupted receipt recovery, native-format idempotency, encrypted primary/linked
KF8 headers, and malformed native record bounds. Its PDF test runs with real qpdf supplied
by the Nix runtime. The module passed a Tycho build before production activation.

On 2026-11-13, the official Fracture export was validated as an EPUB despite its
`.zip` filename. The upload helper queued an unchanged `.epub` copy, the deployed
server service imported it, and a repeat import reported it unchanged. BookOrbit
indexed it in Ebooks library 1 as book 91, file 148. The user confirmed that it
opens correctly in their usual browser.

The in-app browser failed while loading browser-local `blob:` chapter URLs;
the successful normal-browser check established that no server or CSP change
was needed for this symptom. These checks establish the real export-to-reader
path. Subsequent acquisition evidence is recorded below. A further 14 official EPUB exports
were validated and uploaded without changing their contents, bringing the
BookOrbit Ebooks library to 15 present books. These exports omit author metadata;
their Amazon author labels were retained privately for later enrichment.
The account eligibility audit remains incomplete. Amazon's repeated human
checks were completed, but further bulk browser work was paused while evaluating
the requested headless acquisition route. The eligible Turning Point export offered a PDF,
but no valid PDF file has been obtained or queued yet.

## Pinned runtime and completed pilots

The acquisition client is [kindl](https://github.com/bGFiMTI2/kindl), pinned to
commit `a896621dde52fc052a960f4bab7af84036013e23`. Its source archive SHA-256 is
`ab20837688cc1bb492fb42b0ff9b8dc5447eebfeb6e53aef8983b7bb008878be`.
`kindle-runtime.nix` builds it with dependencies from the locked nixpkgs revision;
the Linux runtime uses Python 3.14.10 and Calibre 9.17.0. DeDRM 10.0.35 is pinned
to `b4cab04741b7b81e08fea65169af5480d1cea924`; KFX Input 2.34.2 is hash-pinned.
The official KFX plugin URL rolls forward, so retain a cached copy of the pinned
archive for reproducible restores.

Reviewed patches enforce exact HTTPS destination restrictions and block
redirects, create credentials privately from their first write, and accept long
hidden callback URLs with terminal restoration. The verified personal-document
endpoint adds only `cde-ta-g7g.amazon.com` to the host allowlist. Unknown delivery
hosts fail closed. Automatic discovery of unrelated local Kindle keys is disabled.
Both watermark removal and font deobfuscation are disabled. Eight offline guard
tests passed on Linux, including a 4,000-character hidden paste and interruption.

Authentication uses one interactive browser sign-in and PKCE to register an
emulated Android device; later calls use its saved credentials. Download commands
refresh device credentials, but the reviewed path does not automatically recover
an expired registration using OAuth or create replacement identities. The
[maintainer describes device emulation as experimental](https://github.com/Satsuoni/DeDRM_tools/releases/tag/v10.0.34),
with uncertain account consequences and possible future authentication breakage.
The user explicitly approved the pilot and subsequent server automation.

The isolated Mac Fracture pilot used Calibre 9.18.0, DeDRM 10.0.35, and KFX Input
2.34.2. Its converted EPUB had exactly the same normalized text as the official
export: 77,821 words across 66 spine documents. All 62 TOC entries resolved;
chapter navigation and readable text were verified in Calibre's viewer. The
original BookOrbit copy and reading progress stayed unchanged. The Linux pilot
subsequently passed the same text comparison and a repeat run reported unchanged.
These prove the tested title and runtime, not every library format or indefinite
unattended authentication.

## Automated library acquisition on Tycho

The requested scope includes **every item exposed by the complete library inventory**, including
purchases, Kindle Unlimited and library loans, rentals, samples, dictionaries,
and personal documents. There is no purchase-only filter. Acquisition does not
delete local books when an item disappears from Amazon; downloaded loan copies
do not automatically expire. Expired or withdrawn access can still prevent a
download, and those failures are reported instead of counted as imported.

`bookorbit-kindle-sync.service` is configured for a persistent timer every
15 minutes, without randomized delay. Runs do not overlap; if the shared media
lock is busy, that attempt defers until the next scheduled check. This replaces
the initial hourly schedule with up to ten minutes of jitter.
It reuses the authenticated device from the successful Mac pilot; the Mac and a browser are not needed for ordinary runs. It does not create
new device registrations automatically on authentication failure.

The runtime is pinned in `kindle-runtime.nix`: kindl source plus reviewed patches,
Calibre from the locked nixpkgs revision, and hashed DeDRM/KFX Input plugins.
Downloads permit only reviewed HTTPS hosts and reject redirects. Calibre import,
decryption, and any conversion run in a network namespace
without network access. Personal documents use the separately verified signed
`FSDownloadContent` PDOC route. Legacy BOOKMOBI/PDF payloads are retained; KFX
components can be packaged with or without a voucher, then validated after
processing. A decrypted Calibre export in MOBI, AZW, AZW3, or EPUB is validated
and preserved with its actual suffix. Only KFX requires EPUB conversion. This
avoids expensive and unnecessary dictionary conversion while retaining native
reader features. [BookOrbit lists these native formats](https://bookorbit.app/reader).
The shared media lock excludes
Audible imports, manual Kindle imports, and backup snapshots. A busy lock defers
the run without clearing an existing failure incident.

State and credentials live in `/var/lib/bookorbit-kindle`, owned by root with
0700 directory/0600 file permissions. `inventory.json` records the complete
paginated library, `state.json` records hashes and publication progress, and
`last-run.json` records counts and per-item failures. Detailed conversion logs
and `last-error.json` stay private and can contain sensitive diagnostics; do not
paste them into public issues or notification messages. Original downloaded
packages and processed files are retained. The encrypted backup includes this
state under its `kindle/` directory, excluding disposable `work/` files.

Existing official exports are adopted only when their importer receipt and
current bytes agree. A later run verifies live files rather than trusting file
existence. Source-size/publication metadata changes cause a new conversion;
Amazon does not provide a proven universal edition-update signal through this
connector. Publication uses the existing atomic importer and preserves prior
revisions. Durable prepared hashes allow interrupted receipt updates to resume
without overwriting unrelated external edits.

```sh
sudo systemctl start bookorbit-kindle-sync.service
systemctl status bookorbit-kindle-sync.service bookorbit-kindle-sync.timer
journalctl -u bookorbit-kindle-sync.service --since today
sudo cat /var/lib/bookorbit-kindle/last-run.json
```

Only a complete successful acquisition/import pass advances `last-success`.
Authentication/rate-limit/transport problems stop the run; individual conversion
failures are retained while other books continue. An HTTP 403 with the exact
observed Amazon message that a loan has ended is classified `loan_ended`; it
does not count toward the stop after three unknown consecutive denials. It still
remains a failed item and prevents a complete-success marker. Other 403 responses
are not silently classified as expired loans. The existing ntfy monitor
sends one failure per incident and one recovery after a later complete successful
run. It monitors acquisition separately from the five-minute manual-file importer.
On 2026-11-13 the user confirmed both failure and recovery test notifications
arrived with ntfy backgrounded or the iPhone locked. Authentication remains enabled.

For an authentication failure that requires interactive sign-in, stop the
acquisition timer and let the current media operation finish. In a private SSH
terminal run `sudo bookorbit-kindle-cli user add pilot --replace --region us
--no-browser`, complete Amazon sign-in, and paste the final URL only into its
hidden terminal prompt. This explicitly registers a replacement device identity;
review that step before using it. Restart the timer and run the service after
sign-in succeeds. Completed BookOrbit files remain intact; unfinished encrypted
downloads from a different device identity are fetched again rather than reused.
