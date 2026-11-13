#!/usr/bin/env python3
"""Offline inventory/completion invariants; no Amazon requests."""
import importlib.util
import json
from pathlib import Path
import tempfile
import shutil
import sys
import types
import zipfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1] / "modules/nixos/bookorbit"
spec = importlib.util.spec_from_file_location("sync", ROOT / "kindle-sync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


def item(identifier, origin="Purchase", kind="EBOK"):
    return (f'<meta_data><ASIN>{identifier}</ASIN><title>Test</title>'
            f'<cde_contenttype>{kind}</cde_contenttype><content_size>123</content_size>'
            f'<origins><origin><type>{origin}</type></origin></origins></meta_data>')


def page(body="", cursor="first", more="false", removed=""):
    flag = f"<has_more>{more}</has_more>" if more is not None else ""
    return (f'<response><sync_time>{cursor}</sync_time>{flag}'
            f'<add_update_list>{body}</add_update_list><removal_list>{removed}</removal_list></response>').encode()


class SyncTests(unittest.TestCase):
    def test_all_origins_and_personal_documents_are_kept(self):
        entries = "".join(item(f"B{i:09}", origin) for i, origin in enumerate(
            ["Purchase", "KindleUnlimited", "PublicLibraryLending", "Rental", "Sample", "KindleDictionary"]))
        entries += item("R5FMFNPPFDZN6Y2NAPCPNFRCBGRPMF3Q", "", "PDOC")
        records = sync.inventory(lambda _: page(entries))
        self.assertEqual(len(records), 7)
        self.assertIn("R5FMFNPPFDZN6Y2NAPCPNFRCBGRPMF3Q", records)

    def test_pagination_empty_pages_and_final_omitted_flag(self):
        pages = [page(item("B000000001"), "one", "true"), page("", "two", "true"),
                 page(item("B000000002"), "three", None)]
        requested, pauses = [], []
        def fetch(cursor):
            requested.append(cursor)
            return pages[len(requested) - 1]
        self.assertEqual(set(sync.inventory(fetch, pauses.append)), {"B000000001", "B000000002"})
        self.assertEqual(requested, [None, "one", "two"])
        self.assertEqual(pauses, [10, 10])

    def test_repeated_cursor_and_error_response_fail_closed(self):
        with self.assertRaises(ValueError): sync.inventory(lambda _: page(more="true"), lambda _: None)
        with self.assertRaises(ValueError): sync.parse_page(b"<response><error>failed</error></response>")
        with self.assertRaises(ValueError): sync.parse_page(page(item("../../escape")))

    def test_removal_affects_inventory_not_files(self):
        pages = iter([page(item("B000000001"), "one", "true"),
                      page(removed="<meta_data><ASIN>B000000001</ASIN></meta_data>")])
        self.assertEqual(sync.inventory(lambda _: next(pages), lambda _: None), {})

    def test_existing_official_file_is_adopted_only_with_matching_receipt(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); books = base / "books"; receipts = base / "receipts"
            target = books / "Kindle [B000000001]" / "book.epub"
            target.parent.mkdir(parents=True); receipts.mkdir()
            target.write_bytes(b"validated-book")
            hashed = sync.digest(target)
            receipt = receipts / "B000000001.epub.json"
            receipt.write_text(json.dumps({"sha256": hashed}))
            importer = Mock()
            self.assertEqual(sync.known_existing("B000000001", {"version": "v1"}, None, books, receipts, importer), hashed)
            importer.validate.assert_called_once_with(target, "epub")
            self.assertIsNone(sync.known_existing("B000000001", {"version": "v2"},
                {"version": "v1", "sha256": hashed}, books, receipts, importer))
            target.write_bytes(b"external-edit")
            with self.assertRaises(ValueError):
                sync.known_existing("B000000001", {"version": "v1"}, None, books, receipts, importer)

    def test_missing_target_requires_repair_and_atomic_state_is_private(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.assertIsNone(sync.known_existing("B000000001", {}, None, base, base, Mock()))
            path = base / "state.json"
            sync.save(path, {"complete": True})
            self.assertEqual(json.loads(path.read_text()), {"complete": True})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(base.glob(".state-*")), [])

    def test_conversion_is_network_isolated(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp, patch.object(sync.subprocess, "run") as run:
            sync.offline(["ebook-convert", "source", "output"], Path(temp)/"private.log", {})
            self.assertEqual(run.call_args.args[0][:3], ["unshare", "--net", "--"])


    def test_personal_document_recognizes_mobi_and_rejects_error_body(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            response = Mock()
            response.iter_bytes.return_value = [b"\0" * 60, b"BOOKMOBI", b"synthetic content"]
            context = Mock()
            context.__enter__ = Mock(return_value=response)
            context.__exit__ = Mock(return_value=False)
            client = Mock()
            client.http.stream.return_value = context
            result = sync.personal_document(client, "a" * 32, work)
            self.assertEqual(result.name, "book.azw")
            self.assertEqual(result.read_bytes()[60:68], b"BOOKMOBI")
            requested = client.http.stream.call_args.args[1]
            self.assertTrue(requested.startswith("https://cde-ta-g7g.amazon.com/FionaCDEServiceEngine/FSDownloadContent?type=PDOC&"))
            client._signed_headers.assert_called_once_with("GET", requested)
            result.unlink()
            response.iter_bytes.return_value = [b"<html>Amazon error</html>"]
            with self.assertRaises(ValueError):
                sync.personal_document(client, "a" * 32, work)
            self.assertFalse((work / "book.azw").exists())
            self.assertFalse((work / "book.pdf").exists())

    def test_partial_run_resumes_cached_archive_and_only_marks_full_success(self):
        # Exercise orchestration with fake Amazon modules and real local ledger /
        # receipt files. No account, network, subprocess, or Calibre is involved.
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); state = base / "state"; state.mkdir(mode=0o700)
            config = state / "config.json"; config.write_text("{}"); config.chmod(0o600)
            books = base / "books"; receipts = base / "receipts"
            books.mkdir(); receipts.mkdir()
            args = types.SimpleNamespace(state=state, books=books, receipts=receipts, only=None, scan_only=False)
            credentials = types.SimpleNamespace(serial="SYNTHETIC", account_secrets=["SYNTHETIC"])
            account = types.SimpleNamespace(credentials=credentials)
            store = Mock(accounts=[account])
            client = Mock()
            client.__enter__ = Mock(return_value=client)
            client.__exit__ = Mock(return_value=False)
            client.http.get.return_value.content = page(item("B000000001") + item("B000000002"))
            def download(identifier, output_dir, **kwargs):
                output_dir.mkdir(parents=True)
                (output_dir / "synthetic.azw8").write_bytes(b"synthetic unencrypted KFX")
            client.download.side_effect = download
            imported = []
            def publish(source, library, receipt_dir):
                identifier = source.stem
                target = library / f"Kindle [{identifier}]" / "book.epub"
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                (receipt_dir / f"{identifier}.epub.json").write_text(json.dumps({"sha256":sync.digest(target)}))
                imported.append(identifier)
                return "imported"
            importer = Mock(); importer.import_file.side_effect = publish
            fail = [True]
            def convert(archive, destination, *unused):
                if archive.stem == "B000000002" and fail[0]:
                    raise ValueError("synthetic conversion failure")
                destination.write_bytes(("validated " + archive.stem).encode())
                return destination
            fake_http_error = type("HTTPStatusError", (Exception,), {})
            modules = {
                "kindl.auth": types.SimpleNamespace(AccountStore=Mock(load=Mock(return_value=store))),
                "kindl.client": types.SimpleNamespace(AmazonDeviceClient=Mock(return_value=client), LIBRARY_URL="https://synthetic.invalid/library"),
                "httpx": types.SimpleNamespace(HTTPStatusError=fake_http_error, TransportError=type("TransportError", (Exception,), {})),
            }
            with patch.dict(sys.modules, modules), patch.object(sync, "load_importer", return_value=importer), \
                 patch.object(sync, "offline"), patch.object(sync, "prepare_keys"), \
                 patch.object(sync, "convert", side_effect=convert), \
                 patch.object(sync.shutil, "disk_usage", return_value=types.SimpleNamespace(free=50*1024**3)):
                self.assertEqual(sync.run(args), 1)
                self.assertFalse((state / "last-success").exists())
                summary = json.loads((state / "last-run.json").read_text())
                self.assertEqual(summary["imported"], 1)
                self.assertEqual(set(summary["failed"]), {"B000000002"})
                self.assertEqual(set(json.loads((state/"state.json").read_text())["books"]), {"B000000001"})
                self.assertEqual(client.download.call_count, 2)
                fail[0] = False
                self.assertEqual(sync.run(args), 0)
                self.assertTrue((state / "last-success").exists())
                self.assertEqual(client.download.call_count, 2, "Verified download cache must be reused")
                self.assertEqual(imported, ["B000000001", "B000000002"])
                summary = json.loads((state / "last-run.json").read_text())
                self.assertEqual((summary["unchanged"], summary["imported"], summary["unprocessed"]), (1,1,0))


    def test_package_download_preserves_legacy_formats_and_unencrypted_kfx(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary); source = work / "source"; source.mkdir()
            (source / "manifest.json").write_text("{}")
            payload = source / "content.bin"
            mobi = b"\0" * 60 + b"BOOKMOBI" + b"synthetic payload"
            payload.write_bytes(mobi)
            output = sync.package_download(source, work)
            self.assertEqual(output.suffix, ".azw")
            self.assertEqual(output.read_bytes(), mobi)
            payload.write_bytes(b"%PDF-1.7 synthetic")
            output = sync.package_download(source, work)
            self.assertEqual(output.suffix, ".pdf")
            self.assertEqual(output.read_bytes(), payload.read_bytes())
            payload.unlink()
            (source / "content.azw8").write_bytes(b"synthetic KFX without voucher")
            output = sync.package_download(source, work)
            with zipfile.ZipFile(output) as book:
                self.assertEqual(book.namelist(), ["content.azw8"])
                self.assertIsNone(book.testzip())
            (source / "amzn1.drm-voucher.synthetic").write_bytes(b"synthetic voucher")
            output = sync.package_download(source, work)
            with zipfile.ZipFile(output) as book:
                self.assertIn("amzn1.drm-voucher.synthetic.voucher", book.namelist())
            for path in source.iterdir(): path.unlink()
            (source / "a.bin").write_bytes(mobi)
            (source / "b.bin").write_bytes(mobi)
            with self.assertRaises(ValueError): sync.package_download(source, work)

    def test_prepared_import_repairs_receipt_after_publication_crash(self):
        spec = importlib.util.spec_from_file_location("actual_importer", ROOT / "kindle-import.py")
        importer = importlib.util.module_from_spec(spec); spec.loader.exec_module(importer)
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary); root = base / "state"; books = base / "books"; receipts = base / "receipts"
            (root / "converted").mkdir(parents=True); receipts.mkdir()
            identifier = "B000000001"
            source = root / "converted" / f"{identifier}.epub"; source.write_bytes(b"validated new EPUB")
            target = books / f"Kindle [{identifier}]" / "book.epub"
            target.parent.mkdir(parents=True); shutil.copyfile(source, target)
            receipt = receipts / f"{identifier}.epub.json"
            # Crash occurred after replacing target, before replacing old receipt.
            receipt.write_text(json.dumps({"sha256":"old-file-hash"}))
            prepared = {"version":"v2", "format":"epub", "sha256":sync.digest(source)}
            state = {"books":{identifier:{"version":"v1", "format":"epub", "sha256":"old-file-hash"}},
                     "prepared":{identifier:prepared.copy()}}
            with patch.object(importer, "validate"):
                sync.recover_prepared(identifier, {"version":"v2"}, state, root, books, receipts, importer)
            self.assertEqual(json.loads(receipt.read_text())["sha256"], prepared["sha256"])
            self.assertEqual(state["books"][identifier], prepared)
            self.assertEqual(state["prepared"], {})
            self.assertEqual(json.loads((root/"state.json").read_text())["books"][identifier], prepared)
            self.assertEqual(source.read_bytes(), target.read_bytes())

    def test_prepared_recovery_never_adopts_external_edit_or_invalid_preparation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root/"converted").mkdir(); books = root/"books"; receipts=root/"receipts"
            identifier = "B000000001"
            source=root/"converted"/f"{identifier}.epub";source.write_bytes(b"prepared EPUB")
            target=books/f"Kindle [{identifier}]"/"book.epub";target.parent.mkdir(parents=True)
            target.write_bytes(b"external edit")
            record={"version":"v1"}; prepared={"version":"v1","format":"epub","sha256":sync.digest(source)}
            state={"books":{},"prepared":{identifier:prepared}}
            importer=Mock()
            sync.recover_prepared(identifier,record,state,root,books,receipts,importer)
            self.assertEqual(target.read_bytes(),b"external edit")
            importer.import_file.assert_not_called()
            target.unlink();source.write_bytes(b"corrupted preparation")
            sync.recover_prepared(identifier,record,state,root,books,receipts,importer)
            importer.import_file.assert_not_called()
            self.assertEqual(state["books"],{})
            self.assertIn(identifier,state["prepared"])


    def test_decrypted_native_export_is_validated_and_preserved_without_epub_conversion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / "work").mkdir(); (root / "converted").mkdir()
            archive = root / "source.azw"; archive.write_bytes(b"encrypted source placeholder")
            destination = root / "converted/B000000001.epub"
            exported_path = []
            calls = []
            body = b"decrypted native MOBI bytes"
            def calibre(command, log, env):
                calls.append(command)
                if command[:2] == ["calibredb", "export"]:
                    exported = Path(command[command.index("--to-dir") + 1]); exported.mkdir()
                    payload = exported / "Dictionary.mobi"; payload.write_bytes(body)
                    exported_path.append(payload)
                elif command[:2] != ["calibredb", "add"]:
                    self.fail("Native payload must not invoke ebook-convert")
            importer = Mock()
            with patch.object(sync, "offline", side_effect=calibre):
                result = sync.convert(archive, destination, root, {}, root/"conversion.log", importer)
            self.assertEqual(result, destination.with_suffix(".mobi"))
            self.assertEqual(result.read_bytes(), body)
            self.assertFalse(destination.exists())
            importer.validate.assert_called_once_with(exported_path[0], "mobi")
            self.assertEqual([command[:2] for command in calls], [["calibredb","add"],["calibredb","export"]])
            self.assertEqual(archive.read_bytes(), b"encrypted source placeholder")


    def test_expired_loan_requires_exact_amazon_message(self):
        response = Mock(status_code=403)
        response.json.return_value = {"message":"This book was loaned to you and cannot be downloaded because the loan has ended."}
        self.assertTrue(sync.expired_loan(response))
        response.json.return_value = {"message":"Access denied for this device."}
        self.assertFalse(sync.expired_loan(response))
        response.json.return_value = {"message":"loan has ended"}
        self.assertFalse(sync.expired_loan(response))
        response.json.side_effect = ValueError("HTML error body")
        self.assertFalse(sync.expired_loan(response))


if __name__ == "__main__": unittest.main()
