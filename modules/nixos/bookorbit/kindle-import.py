#!/usr/bin/env python3
"""Import completed exports. This does not sign in to or download from Amazon."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
import zipfile


FONT_OBFUSCATION = {
    "http://www.idpf.org/2008/embedding",
    "http://ns.adobe.com/pdf/enc#RC",
}


def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def validate_mobi(path):
    """Validate PalmDB bounds, PalmDOC encryption, and linked MOBI/KF8 headers.

    Field layouts follow Calibre's ebooks/mobi/reader/{headers,mobi6}.py.
    This checks the container, not a full render or decompression of its text.
    """
    with path.open("rb") as stream:
        size = os.fstat(stream.fileno()).st_size
        pdb = stream.read(78)
        if len(pdb) != 78 or pdb[60:68] != b"BOOKMOBI":
            raise ValueError("not a MOBI PalmDB file")
        count = struct.unpack_from(">H", pdb, 76)[0]
        table_end = 78 + count * 8
        if count < 2 or table_end > size:
            raise ValueError("truncated MOBI record table")
        table = stream.read(count * 8)
        offsets = [struct.unpack_from(">I", table, i * 8)[0] for i in range(count)]
        if (offsets[0] < table_end or any(offset > size for offset in offsets)
                or any(a > b for a, b in zip(offsets, offsets[1:]))):
            raise ValueError("invalid MOBI record bounds")
        offsets.append(size)

        def record(index):
            length = offsets[index + 1] - offsets[index]
            if length > 8 * 1024**2:
                raise ValueError("MOBI metadata record exceeds validation limit")
            stream.seek(offsets[index])
            return stream.read(length)

        pending, checked = [0], set()
        while pending:
            index = pending.pop()
            if index in checked:
                raise ValueError("cyclic MOBI header link")
            checked.add(index)
            header = record(index)
            if len(header) < 40 or header[16:20] != b"MOBI":
                raise ValueError("truncated or invalid MOBI header")
            compression = struct.unpack_from(">H", header, 0)[0]
            text_length = struct.unpack_from(">I", header, 4)[0]
            text_records, record_size, encryption = struct.unpack_from(">HHH", header, 8)
            if encryption != 0:
                raise ValueError("MOBI contains encrypted content")
            if compression not in (1, 2, 17480):
                raise ValueError("unsupported MOBI compression")
            if not text_records or not record_size or index + text_records >= count:
                raise ValueError("truncated MOBI text records")
            lengths = [offsets[i + 1] - offsets[i] for i in range(index + 1, index + 1 + text_records)]
            if any(length <= 0 for length in lengths) or (compression == 1 and sum(lengths) < text_length):
                raise ValueError("truncated MOBI text payload")
            mobi_length = struct.unpack_from(">I", header, 20)[0]
            if mobi_length < 24 or 16 + mobi_length > len(header):
                raise ValueError("invalid MOBI header length")
            if mobi_length < 116 or not (struct.unpack_from(">I", header, 128)[0] & 0x40):
                continue
            exth = 16 + mobi_length
            if len(header) < exth + 12 or header[exth:exth + 4] != b"EXTH":
                raise ValueError("truncated MOBI EXTH header")
            length, entries = struct.unpack_from(">II", header, exth + 4)
            end = exth + length
            if length < 12 or end > len(header) or entries > (length - 12) // 8:
                raise ValueError("invalid MOBI EXTH bounds")
            position = exth + 12
            for _ in range(entries):
                if position + 8 > end:
                    raise ValueError("truncated MOBI EXTH record")
                kind, length = struct.unpack_from(">II", header, position)
                if length < 8 or position + length > end:
                    raise ValueError("invalid MOBI EXTH record bounds")
                if kind == 121:
                    if length != 12:
                        raise ValueError("invalid MOBI KF8 header reference")
                    other = struct.unpack_from(">I", header, position + 8)[0]
                    if other != 0xffffffff:
                        if not 1 <= other < count or record(other - 1) != b"BOUNDARY":
                            raise ValueError("invalid MOBI KF8 boundary")
                        pending.append(other)
                position += length


def validate(path, extension):
    if extension == "epub":
        with zipfile.ZipFile(path) as book:
            if any(entry.flag_bits & 1 for entry in book.infolist()):
                raise ValueError("encrypted ZIP entries are not supported")
            if book.read("mimetype").strip() != b"application/epub+zip":
                raise ValueError("not an EPUB archive")
            if book.testzip() is not None:
                raise ValueError("damaged EPUB archive")
            root = ET.fromstring(book.read("META-INF/container.xml"))
            packages = root.findall(".//{*}rootfile")
            if not packages:
                raise ValueError("EPUB has no package document")
            for package in packages:
                ET.fromstring(book.read(package.attrib["full-path"]))
            if "META-INF/encryption.xml" in book.namelist():
                encryption = ET.fromstring(book.read("META-INF/encryption.xml"))
                for method in encryption.findall(".//{*}EncryptionMethod"):
                    if method.get("Algorithm") not in FONT_OBFUSCATION:
                        raise ValueError("EPUB contains encrypted content; export a DRM-free file")
    elif extension in ("mobi", "azw", "azw3"):
        validate_mobi(path)
    elif extension == "pdf":
        encrypted = subprocess.run(["qpdf", "--is-encrypted", str(path)], capture_output=True)
        if encrypted.returncode != 2:
            raise ValueError("PDF is encrypted or unreadable; export a DRM-free file")
        checked = subprocess.run(["qpdf", "--check", str(path)], capture_output=True)
        if checked.returncode not in (0, 3):
            raise ValueError("damaged PDF")
    else:
        raise ValueError("unsupported ebook format")


def regular(path):
    return stat.S_ISREG(path.lstat().st_mode)


def write_receipt(receipt, temporary, asin, new_hash, source, target):
    record = Path(temporary) / "receipt.json"
    record.write_text(json.dumps({"asin": asin, "sha256": new_hash, "source": source.name,
                                  "target": str(target), "imported_at": int(time.time())}) + "\n")
    record.chmod(0o600)
    os.replace(record, receipt)


def import_file(source, books, state, owner=(2000, 2000)):
    match = re.fullmatch(r"([A-Z0-9]{10}|[A-Za-z0-9]{32})\.(epub|pdf|mobi|azw|azw3)", source.name)
    if not match or not regular(source):
        raise ValueError("expected a regular ASIN.epub, .pdf, .mobi, .azw, or .azw3 file")
    asin, extension = match.groups()
    folder = books / f"Kindle [{asin}]"
    target = folder / f"book.{extension}"
    receipt = state / f"{asin}.{extension}.json"
    if folder.is_symlink() or target.is_symlink() or receipt.is_symlink():
        raise ValueError("refusing a symlink destination")
    # Only completed copies are validated or published. Changing uploads fail closed.
    with tempfile.TemporaryDirectory(prefix="staging-", dir=state) as temporary:
        staged = Path(temporary) / target.name
        descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as original, staged.open("xb") as copied:
            before = os.fstat(original.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise ValueError("source is not a regular file")
            shutil.copyfileobj(original, copied)
            after = os.fstat(original.fileno())
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError("source changed during copy; retry after upload completes")
        new_hash = digest(staged)
        if target.exists():
            if not regular(target):
                raise ValueError("destination is not a regular file")
            old_hash = digest(target)
            if old_hash == new_hash:
                # Complete an interrupted publication that had not yet saved its receipt.
                if not receipt.exists() or json.loads(receipt.read_text()).get("sha256") != new_hash:
                    validate(staged, extension)
                    write_receipt(receipt, temporary, asin, new_hash, source, target)
                return "unchanged"
            previous = json.loads(receipt.read_text()) if receipt.exists() else {}
            if previous.get("sha256") != old_hash:
                raise ValueError("destination changed outside this importer; preserving both files")
        else:
            old_hash = None
        validate(staged, extension)
        # Keep room for the live copy, backup staging, and ordinary server work.
        if shutil.disk_usage(books).free < staged.stat().st_size * 2 + 1024**3:
            raise ValueError("insufficient space for import and backup")
        folder.mkdir(exist_ok=True, mode=0o750)
        os.chown(folder, *owner)
        if old_hash:
            archive = state / "revisions" / asin
            archive.mkdir(parents=True, exist_ok=True, mode=0o700)
            saved = archive / f"{old_hash}.{extension}"
            if not saved.exists():
                # Copy, rather than hard-link, to preserve an independent prior revision.
                shutil.copyfile(target, saved)
                saved.chmod(0o600)
            if digest(saved) != old_hash:
                raise ValueError("prior revision archive failed verification")
        staged.chmod(0o640)
        os.chown(staged, *owner)
        with staged.open("rb") as ready:
            os.fsync(ready.fileno())
        os.replace(staged, target)
        write_receipt(receipt, temporary, asin, new_hash, source, target)
    return "updated" if old_hash else "imported"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inbox", type=Path, required=True)
    parser.add_argument("--books", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error("run through sudo bookorbit-kindle-import")
    errors = 0
    for source in sorted(args.inbox.iterdir()):
        if source.name.startswith(".") or source.suffix not in (".epub", ".pdf", ".mobi", ".azw", ".azw3"):
            continue  # Uploads ending in .part are never imported.
        try:
            print(source.name, import_file(source, args.books, args.state), flush=True)
        except (OSError, ValueError, KeyError, ET.ParseError, zipfile.BadZipFile) as error:
            print(source.name, "FAILED:", error, flush=True)
            errors += 1
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
