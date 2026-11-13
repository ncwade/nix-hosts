"""Download the complete Kindle library and publish validated ebooks offline."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from urllib.parse import urlencode
import xml.etree.ElementTree as ET
import zipfile


IDENTIFIER = re.compile(r"(?:[A-Z0-9]{10}|[A-Za-z0-9]{32})\Z")
FORMATS = ("epub", "pdf", "mobi", "azw", "azw3")


def save(path, data):
    fd, name = tempfile.mkstemp(prefix=".state-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def expired_loan(response):
    """Recognize Amazon's explicit per-book expiry, without masking other denials."""
    try:
        message = response.json().get("message", "")
    except (ValueError, AttributeError):
        return False
    return message == "This book was loaned to you and cannot be downloaded because the loan has ended."


def parse_page(content):
    root = ET.fromstring(content)
    # Namespace-neutral access, but reject unexpected/error responses.
    for node in root.iter():
        node.tag = node.tag.rsplit("}", 1)[-1]
    if root.tag != "response" or root.find("add_update_list") is None or not root.findtext("sync_time"):
        raise ValueError("Incomplete library response")
    more = root.findtext("has_more", "false").lower()
    if more not in ("true", "false"):
        raise ValueError("Invalid pagination status")
    records = {}
    for meta in root.findall("add_update_list/meta_data"):
        identifier = meta.findtext("ASIN", "")
        if not IDENTIFIER.fullmatch(identifier):
            raise ValueError("Unrecognized library identifier; inventory would be incomplete")
        record = {name: meta.findtext(name, "") for name in
                  ("title", "cde_contenttype", "content_type", "publication_date", "content_size")}
        record["authors"] = [e.text or "" for e in meta.findall("authors/author")]
        record["origins"] = sorted({e.text or "" for e in meta.findall("origins/origin/type")})
        # Changes in source size/publication metadata trigger a new validated revision.
        record["version"] = hashlib.sha256(json.dumps(
            [record[k] for k in ("content_size", "publication_date", "content_type")]).encode()).hexdigest()
        records[identifier] = record
    removed = []
    for node in root.findall("removal_list/*"):
        identifier = node.findtext("ASIN") or node.get("key") or (node.text or "").strip()
        if IDENTIFIER.fullmatch(identifier):
            removed.append(identifier)
    interval = int(root.findtext("min_sync_metadata_request_interval", "10"))
    if not 0 <= interval <= 300:
        raise ValueError("Unexpected library polling interval")
    return records, removed, more == "true", root.findtext("sync_time"), max(10, interval)


def inventory(fetch, pause=time.sleep):
    result, seen, cursor = {}, set(), None
    for _ in range(100):
        entries, removed, more, next_cursor, interval = parse_page(fetch(cursor))
        result.update(entries)
        for identifier in removed:
            result.pop(identifier, None)
        if not more:
            return result
        if next_cursor in seen:
            raise ValueError("Library pagination did not advance")
        seen.add(next_cursor)
        cursor = next_cursor
        pause(interval)
    raise ValueError("Library pagination exceeded safety bound")


def load_importer():
    spec = importlib.util.spec_from_file_location("bookorbit_importer", os.environ["KINDLE_IMPORTER"])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare_keys(credentials, directory):
    path = directory / "plugins/dedrm.json"
    config = json.loads(path.read_text()) if path.exists() else {}
    config.update(configured=True, remove_watermarks=False, deobfuscate_fonts=False,
                  serials=[credentials.serial],
                  pids=[credentials.serial + secret for secret in credentials.account_secrets],
                  kindlekeys={}, androidkeys={}, kindleextrakeyfile="")
    save(path, config)


def offline(command, log, env, timeout=600):
    with log.open("ab") as stream:
        subprocess.run(["unshare", "--net", "--", *command], env=env,
                       stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=timeout)


def convert(archive, destination, root, env, log, importer):
    if archive.suffix == ".pdf":
        importer.validate(archive, "pdf")
        shutil.copyfile(archive, destination)
        return destination
    with tempfile.TemporaryDirectory(prefix="convert-", dir=root / "work") as temporary:
        work = Path(temporary)
        library, exported = work / "library", work / "exported"
        offline(["calibredb", "add", str(archive), "--with-library", str(library)], log, env)
        offline(["calibredb", "export", "--all", "--formats", "kfx-zip,kfx,azw,azw3,mobi,epub", "--to-dir", str(exported),
                 "--dont-save-cover", "--dont-write-opf", "--single-dir", "--with-library", str(library)], log, env)
        payloads = [p for p in exported.iterdir() if p.suffix in (".kfx", ".kfx-zip", ".azw", ".azw3", ".mobi", ".epub")]
        if len(payloads) != 1:
            raise ValueError("Conversion did not export one book")
        payload = payloads[0]
        if payload.suffix in (".mobi", ".azw", ".azw3", ".epub"):
            importer.validate(payload, payload.suffix[1:])
            destination = destination.with_suffix(payload.suffix)
            os.replace(payload, destination)
            return destination
        output = work / "book.epub"
        offline(["ebook-convert", str(payloads[0]), str(output)], log, env)
        importer.validate(output, "epub")
        os.replace(output, destination)
        return destination


def known_existing(identifier, record, previous, books, receipts, importer):
    extension = previous.get("format", "epub") if previous else "epub"
    if extension not in FORMATS:
        raise ValueError("Invalid completion format")
    target = books / f"Kindle [{identifier}]" / f"book.{extension}"
    receipt = receipts / f"{identifier}.{extension}.json"
    if not target.is_file() or target.is_symlink() or not receipt.is_file() or receipt.is_symlink():
        return None
    current_hash = digest(target)
    if json.loads(receipt.read_text()).get("sha256") != current_hash:
        raise ValueError("BookOrbit file changed outside its importer")
    if previous and previous.get("version") != record["version"]:
        return None
    if previous and previous.get("sha256") != current_hash:
        raise ValueError("Published file differs from acquisition receipt")
    importer.validate(target, extension)
    return current_hash


def personal_document(client, identifier, work):
    # Documented FSDownloadContent route; tested with this account/device.
    url = "https://cde-ta-g7g.amazon.com/FionaCDEServiceEngine/FSDownloadContent?" + urlencode({
        "type": "PDOC", "key": identifier, "is_archived_items": "1", "software_rev": "1184370688"})
    path = work / "personal-document.part"
    with client.http.stream("GET", url, headers=client._signed_headers("GET", url)) as response:
        response.raise_for_status()
        with path.open("wb") as output:
            for chunk in response.iter_bytes():
                output.write(chunk)
    with path.open("rb") as source:
        header = source.read(68)
    if header.startswith(b"%PDF-"):
        extension = ".pdf"
    elif header[60:68] == b"BOOKMOBI":
        extension = ".azw"
    else:
        raise ValueError("Personal document response is not recognized MOBI/PDF")
    ready = work / ("book" + extension)
    path.rename(ready)
    return ready


def package_download(source, work):
    """Preserve legacy payloads and KFX, including unencrypted sample bundles."""
    files = [p for p in source.iterdir() if p.is_file() and p.name != "manifest.json"]
    legacy = []
    for path in files:
        with path.open("rb") as stream:
            header = stream.read(68)
        if header.startswith(b"%PDF-"):
            legacy.append((path, ".pdf"))
        elif header[60:68] == b"BOOKMOBI":
            legacy.append((path, ".azw"))
    if legacy:
        if len(legacy) != 1:
            raise ValueError("Ambiguous legacy download payload")
        ready = work / ("book" + legacy[0][1])
        shutil.copyfile(legacy[0][0], ready)
        return ready
    components = [p for p in files if p.suffix.lower() in (".azw8", ".azw9", ".md", ".res", ".voucher")
                  or p.name.startswith("amzn1.drm-voucher.")]
    if not any(p.suffix.lower() in (".azw8", ".azw9") for p in components):
        raise ValueError("No supported ebook payload in download")
    ready = work / "book.kfx-zip"
    with zipfile.ZipFile(ready, "w", compression=zipfile.ZIP_STORED) as archive:
        for path in components:
            name = path.name
            if name.startswith("amzn1.drm-voucher.") and not name.endswith(".voucher"):
                name += ".voucher"
            archive.write(path, name)
    return ready


def recover_prepared(identifier, record, state, root, books, receipts, importer):
    prepared = state.get("prepared", {}).get(identifier)
    if not prepared or prepared.get("version") != record["version"] or prepared.get("format") not in FORMATS:
        return
    extension = prepared["format"]
    source = root / "converted" / f"{identifier}.{extension}"
    target = books / f"Kindle [{identifier}]" / f"book.{extension}"
    if not source.is_file() or source.is_symlink() or digest(source) != prepared.get("sha256"):
        return
    if target.exists() and (target.is_symlink() or digest(target) != prepared["sha256"]):
        return
    # Complete publication/receipt interrupted after the durable preparation.
    importer.import_file(source, books, receipts)
    state["books"][identifier] = prepared
    state["prepared"].pop(identifier)
    save(root / "state.json", state)


def run(args):
    from kindl.auth import AccountStore
    from kindl.client import AmazonDeviceClient, LIBRARY_URL
    import httpx
    root = args.state
    for directory in (root, root / "work", root / "downloads", root / "converted", root / "logs"):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        if directory.is_symlink() or directory.stat().st_mode & 0o077:
            raise ValueError("Private state directory required")
    config = root / "config.json"
    if config.is_symlink() or config.stat().st_mode & 0o077:
        raise ValueError("Private credentials required")
    store = AccountStore.load(config)
    if len(store.accounts) != 1:
        raise ValueError("Expected one Kindle account")
    account = store.accounts[0]
    device_hash = hashlib.sha256(account.credentials.serial.encode()).hexdigest()
    importer = load_importer()
    ledger = root / "state.json"
    state = json.loads(ledger.read_text()) if ledger.exists() else {"books": {}}
    with AmazonDeviceClient(account.credentials) as client:
        client.refresh_device_credentials()
        store.save(config)
        def fetch(cursor):
            query = {"item_count": 1000}
            if cursor:
                query["last_sync_time"] = cursor
            url = LIBRARY_URL + "?" + urlencode(query)
            response = client.http.get(url, headers=client._signed_headers("GET", url, reason="Registration"))
            response.raise_for_status()
            return response.content
        items = inventory(fetch)
        save(root / "inventory.json", items)
        print(f"Complete inventory: {len(items)} items; origins {dict(Counter(o for r in items.values() for o in r['origins']))}", flush=True)
        if args.scan_only:
            return 0
        selected = sorted(items)
        if args.only:
            if args.only not in items:
                raise ValueError("Requested pilot title is absent from library")
            selected = [args.only]
        if not account.credentials.account_secrets:
            client.restore_account_secrets()
            store.save(config)
        env = {**os.environ, "CALIBRE_CONFIG_DIRECTORY": str(root / "calibre-config"),
               "CALIBRE_TEMP_DIR": str(root / "work"), "QT_QPA_PLATFORM": "offscreen"}
        offline(["bookorbit-kindle-init-calibre"], root / "logs/initialize.log", env)
        prepare_keys(account.credentials, root / "calibre-config")
        errors, imported, unchanged, denied = {}, 0, 0, 0
        for identifier in selected:
            record = items[identifier]
            stage = "existing-file validation"
            try:
                recover_prepared(identifier, record, state, root, args.books, args.receipts, importer)
                previous = state["books"].get(identifier)
                existing = known_existing(identifier, record, previous, args.books, args.receipts, importer)
                if existing:
                    state["books"][identifier] = {"version": record["version"], "sha256": existing,
                                                  "format": previous.get("format", "epub") if previous else "epub"}
                    unchanged += 1
                    save(ledger, state)
                    continue
                if shutil.disk_usage(root).free < 10 * 1024**3:
                    raise OSError("Disk reserve reached")
                stage = "download"
                cached = state.get("archives", {}).get(identifier, {})
                suffix = cached.get("suffix", ".kfx-zip")
                if suffix not in (".kfx-zip", ".azw", ".pdf"):
                    raise ValueError("Invalid archive format")
                archive = root / "downloads" / f"{identifier}{suffix}"
                if not (archive.is_file() and cached.get("version") == record["version"]
                        and cached.get("device") == device_hash and cached.get("sha256") == digest(archive)):
                    with tempfile.TemporaryDirectory(prefix="download-", dir=root / "work") as temporary:
                        if record["cde_contenttype"] == "PDOC":
                            ready = personal_document(client, identifier, Path(temporary))
                        else:
                            source = Path(temporary) / "resources"
                            client.download(identifier, source, destination=source)
                            ready = package_download(source, Path(temporary))
                            if ready.suffix == ".kfx-zip":
                                with zipfile.ZipFile(ready) as zipped:
                                    if zipped.testzip() is not None:
                                        raise ValueError("Incomplete downloaded archive")
                        archive = root / "downloads" / (identifier + ready.suffix)
                        os.replace(ready, archive)
                    state.setdefault("archives", {})[identifier] = {"version": record["version"], "sha256": digest(archive),
                                                                  "suffix": archive.suffix, "device": device_hash}
                    save(ledger, state)
                stage = "conversion"
                extension = "pdf" if archive.suffix == ".pdf" else "epub"
                output = root / "converted" / f"{identifier}.{extension}"
                output = convert(archive, output, root, env, root / "logs" / f"{identifier}.log", importer)
                extension = output.suffix[1:]
                stage = "import"
                state.setdefault("prepared", {})[identifier] = {"version": record["version"], "sha256": digest(output), "format": extension}
                save(ledger, state)
                result = importer.import_file(output, args.books, args.receipts)
                state["books"][identifier] = state["prepared"].pop(identifier)
                save(ledger, state)
                imported += 1
                denied = 0
                print(f"{identifier}: {result}", flush=True)
            except Exception as error:
                # HTTP messages can contain signed URLs; never put them in the journal/alerts.
                status = error.response.status_code if isinstance(error, httpx.HTTPStatusError) else None
                errors[identifier] = {"stage": stage, "error": type(error).__name__, "http_status": status}
                ended = status == 403 and expired_loan(error.response)
                if ended:
                    errors[identifier]["reason"] = "loan_ended"
                print(f"{identifier}: FAILED during {stage} ({type(error).__name__}, HTTP {status})", flush=True)
                if status in (401, 429) or (stage == "download" and isinstance(error, (httpx.TransportError, RuntimeError))):
                    break  # Authentication/rate-limit/network/destination guard: no hammering.
                denied = denied + 1 if status == 403 and not ended else 0
                if denied >= 3 or isinstance(error, OSError):
                    break
        summary = {"checked_at": int(time.time()), "inventory": len(items), "selected": len(selected),
                   "imported": imported, "unchanged": unchanged, "failed": errors,
                   "unprocessed": len(selected) - imported - unchanged - len(errors)}
        save(root / "last-run.json", summary)
        print(f"Run complete: {imported} imported, {unchanged} unchanged, {len(errors)} failed, {summary['unprocessed']} unprocessed.", flush=True)
        if errors or summary["unprocessed"]:
            return 1
        if not args.only:
            (root / "last-success").touch()
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state", type=Path, default=Path("/var/lib/bookorbit-kindle"))
    parser.add_argument("--books", type=Path, default=Path("/srv/books/ebooks"))
    parser.add_argument("--receipts", type=Path, default=Path("/srv/books/.kindle-import"))
    parser.add_argument("--only")
    parser.add_argument("--scan-only", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        return run(args)
    except Exception as error:
        if args.state.is_dir() and not args.state.is_symlink() and not (args.state.stat().st_mode & 0o077):
            import traceback
            save(args.state / "last-error.json", {"error": type(error).__name__, "traceback": traceback.format_exc()})
        print(f"Kindle acquisition failed ({type(error).__name__}); credentials and response bodies suppressed.", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
