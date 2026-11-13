#!/usr/bin/env python3
"""Exercise import/update preservation and rejection with real small export files."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("kindle_import", ROOT / "modules/nixos/bookorbit/kindle-import.py")
kindle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kindle)


def epub(path, title="Example", encrypted=False):
    with zipfile.ZipFile(path, "w") as book:
        book.writestr("mimetype", "application/epub+zip")
        book.writestr("META-INF/container.xml", '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>')
        book.writestr("book.opf", '<package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>' + title + '</dc:title></metadata><manifest/><spine/></package>')
        if encrypted:
            book.writestr("META-INF/encryption.xml", '<encryption><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/></EncryptedData></encryption>')


def pdf(path):
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>']
    result = bytearray(b'%PDF-1.4\n'); offsets = [0]
    for index, content in enumerate(objects, 1):
        offsets.append(len(result)); result.extend(f'{index} 0 obj\n'.encode() + content + b'\nendobj\n')
    start = len(result); result.extend(b'xref\n0 4\n0000000000 65535 f \n')
    for offset in offsets[1:]: result.extend(f'{offset:010} 00000 n \n'.encode())
    result.extend(f'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode())
    path.write_bytes(result)


def mobi(path, encrypted=0, joint=False, secondary_encrypted=0):
    text = b"<html><body><p>Synthetic MOBI dictionary entry.</p></body></html>"
    def header(version, encryption, next_header=None):
        result = bytearray(248)
        struct.pack_into(">HHIHHHH", result, 0, 1, 0, len(text), 1, 4096, encryption, 0)
        result[16:20] = b"MOBI"
        struct.pack_into(">IIIII", result, 20, 232, 2, 65001, 123, version)
        struct.pack_into(">I", result, 104, version)
        if next_header is not None:
            struct.pack_into(">I", result, 128, 0x40)
            result.extend(b"EXTH" + struct.pack(">IIIII", 24, 1, 121, 12, next_header))
        return bytes(result)
    records = [header(6, encrypted, 3 if joint else None), text]
    if joint: records.extend([b"BOUNDARY", header(8, secondary_encrypted), text])
    pdb = bytearray(78)
    pdb[:8] = b"Example\0"
    pdb[60:68] = b"BOOKMOBI"
    struct.pack_into(">H", pdb, 76, len(records))
    offset = 78 + len(records) * 8 + 2
    for number, record in enumerate(records):
        pdb.extend(struct.pack(">II", offset, number))
        offset += len(record)
    path.write_bytes(pdb + b"\0\0" + b"".join(records))


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.books = self.root / "books"; self.books.mkdir()
        self.state = self.root / "state"; self.state.mkdir()
        self.source = self.root / "B012345678.epub"
        self.target = self.books / "Kindle [B012345678]/book.epub"
        epub(self.source)

    def tearDown(self): self.tmp.cleanup()

    def run_import(self):
        return kindle.import_file(self.source, self.books, self.state, (os.getuid(), os.getgid()))

    def test_import_and_repeat_preserve_target(self):
        self.assertEqual(self.run_import(), "imported")
        before = self.target.stat()
        self.assertEqual(self.run_import(), "unchanged")
        self.assertEqual(self.target.stat().st_ino, before.st_ino)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        self.assertFalse(list(self.state.glob("staging-*")))

    def test_update_preserves_original_revision(self):
        self.run_import(); old = self.target.read_bytes()
        old_hash = kindle.digest(self.target)
        epub(self.source, title="Revised")
        self.assertEqual(self.run_import(), "updated")
        self.assertEqual((self.state / "revisions/B012345678" / f"{old_hash}.epub").read_bytes(), old)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())

    def test_personal_document_identifier_imports_without_path_aliasing(self):
        identifier = "R5FMFNPPFDZN6Y2NAPCPNFRCBGRPMF3Q"
        self.source = self.root / f"{identifier}.epub"
        epub(self.source)
        self.assertEqual(self.run_import(), "imported")
        self.assertTrue((self.books / f"Kindle [{identifier}]" / "book.epub").is_file())
        self.assertEqual(self.run_import(), "unchanged")

    def test_external_change_is_not_overwritten(self):
        self.run_import(); self.target.write_bytes(b"An independent replacement")
        with self.assertRaisesRegex(ValueError, "outside this importer"): self.run_import()
        self.assertEqual(self.target.read_bytes(), b"An independent replacement")

    def test_drm_and_broken_exports_are_not_published(self):
        epub(self.source, encrypted=True)
        with self.assertRaisesRegex(ValueError, "encrypted content"): self.run_import()
        self.assertFalse(self.target.exists())
        self.source.write_bytes(b"an HTML login page")
        with self.assertRaises(zipfile.BadZipFile): self.run_import()
        self.assertFalse(self.target.exists())

    def test_symlink_is_not_followed(self):
        real = self.root / "original.epub"; self.source.rename(real); self.source.symlink_to(real)
        with self.assertRaisesRegex(ValueError, "regular"): self.run_import()
        self.assertFalse(self.target.exists())

    def test_interrupted_receipt_recovers_without_copying_again(self):
        self.run_import(); inode = self.target.stat().st_ino
        (self.state / "B012345678.epub.json").unlink()
        self.assertEqual(self.run_import(), "unchanged")
        self.assertEqual(self.target.stat().st_ino, inode)
        self.assertEqual(json.loads((self.state / "B012345678.epub.json").read_text())["sha256"], kindle.digest(self.source))

    def test_upload_mutating_during_copy_is_not_published(self):
        original = shutil.copyfileobj
        def mutate(src, dst):
            original(src, dst)
            self.source.write_bytes(b"incomplete replacement")
        with patch.object(kindle.shutil, "copyfileobj", mutate):
            with self.assertRaisesRegex(ValueError, "changed during copy"): self.run_import()
        self.assertFalse(self.target.exists())


    def test_native_mobi_azw_azw3_import_and_repeat_preserve_bytes(self):
        for extension in ("mobi", "azw", "azw3"):
            with self.subTest(extension=extension):
                self.source = self.root / f"B012345678.{extension}"
                mobi(self.source, joint=extension == "azw3")
                target = self.books / f"Kindle [B012345678]/book.{extension}"
                self.assertEqual(self.run_import(), "imported")
                inode = target.stat().st_ino
                self.assertEqual(self.run_import(), "unchanged")
                self.assertEqual(target.stat().st_ino, inode)
                self.assertEqual(target.read_bytes(), self.source.read_bytes())

    def test_native_drm_in_either_mobi_or_linked_kf8_is_rejected(self):
        self.source = self.root / "B012345678.azw3"
        for primary, secondary in ((1,0), (2,0), (0,2)):
            with self.subTest(primary=primary, secondary=secondary):
                mobi(self.source, encrypted=primary, joint=True, secondary_encrypted=secondary)
                with self.assertRaisesRegex(ValueError, "encrypted"):
                    self.run_import()
                self.assertFalse((self.books / "Kindle [B012345678]/book.azw3").exists())

    def test_native_truncated_and_out_of_bounds_records_are_rejected(self):
        self.source = self.root / "B012345678.mobi"; mobi(self.source)
        original = self.source.read_bytes()
        header_offset = struct.unpack_from(">I", original, 78)[0]
        cases = [original[:77], original[:90], original[:-15]]
        for position, fmt, value in ((86, ">I", len(original)+1),
                                      (78, ">I", 10),
                                      (header_offset+8, ">H", 500),
                                      (header_offset+20, ">I", 9999)):
            malformed = bytearray(original); struct.pack_into(fmt, malformed, position, value)
            cases.append(malformed)
        for content in cases:
            self.source.write_bytes(content)
            with self.assertRaises(ValueError): self.run_import()
        self.assertFalse((self.books / "Kindle [B012345678]/book.mobi").exists())

    def test_native_invalid_kf8_link_and_exth_bounds_are_rejected(self):
        self.source = self.root / "B012345678.azw3"; mobi(self.source, joint=True)
        original = self.source.read_bytes(); start = struct.unpack_from(">I", original, 78)[0]
        for position, value in ((start+248+4, 99999), (start+248+20, 99)):
            content=bytearray(original);struct.pack_into(">I",content,position,value)
            self.source.write_bytes(content)
            with self.assertRaises(ValueError): self.run_import()
        self.assertFalse((self.books / "Kindle [B012345678]/book.azw3").exists())

    @unittest.skipUnless(shutil.which("qpdf"), "qpdf supplied by Nix runtime")
    def test_real_pdf_and_encrypted_pdf(self):
        source = self.root / "B012345678.pdf"; pdf(source)
        self.assertEqual(kindle.import_file(source, self.books, self.state, (os.getuid(), os.getgid())), "imported")
        locked = self.root / "locked.pdf"
        subprocess.run(["qpdf", "--encrypt", "reader", "owner", "256", "--", str(source), str(locked)], check=True)
        with self.assertRaisesRegex(ValueError, "encrypted"): kindle.validate(locked, "pdf")


if __name__ == "__main__": unittest.main()
