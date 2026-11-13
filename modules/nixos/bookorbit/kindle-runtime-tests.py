import contextlib
import io
import json
import os
import errno
import hashlib
import pty
import select
import signal
import sys
import termios
import time
from pathlib import Path
import socket
import stat
import tempfile
import unittest
from unittest.mock import patch

import click
import httpx
from kindl.auth import _write_private_json
from kindl.cli import _prompt_callback
from kindl.client import AmazonDeviceClient
from kindl.pilot_guard import check_destination


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.network = patch.object(socket.socket, "connect", side_effect=AssertionError("network forbidden"))
        self.network.start()
        self.addCleanup(self.network.stop)

    def test_unknown_destination_rejected_before_transport_and_signing(self):
        blocked = ["http://api.amazon.com/auth/token", "https://api.amazon.com.evil.test/x",
                   "https://evil.test/?secret=DO_NOT_LOG", "https://127.0.0.1/x",
                   "https://api.amazon.com:8443/x", "https://user:pass@api.amazon.com/x",
                   "https://api.amazon.com/x#fragment", "file:///private/tmp/book"]
        sent = []
        with patch("kindl.client.httpx.HTTPTransport", return_value=httpx.MockTransport(
                lambda req: sent.append(req) or httpx.Response(200))):
            with AmazonDeviceClient() as client:
                for url in blocked:
                    with self.subTest(url=url):
                        with self.assertRaises(RuntimeError) as error:
                            client.http.get(url)
                        self.assertNotIn("DO_NOT_LOG", str(error.exception))
                        with self.assertRaisesRegex(RuntimeError, "blocked"):
                            client._signed_headers("GET", url)
        self.assertEqual(sent, [])

    def test_reviewed_https_host_allowed(self):
        sent = []
        with patch("kindl.client.httpx.HTTPTransport", return_value=httpx.MockTransport(
                lambda req: sent.append(req.url.host) or httpx.Response(200))):
            with AmazonDeviceClient() as client:
                self.assertEqual(client.http.get("https://api.amazon.com/auth/token").status_code, 200)
                self.assertEqual(client.http.get("https://cde-ta-g7g.amazon.com/FionaCDEServiceEngine/FSDownloadContent?type=PDOC&key=SYNTHETIC").status_code, 200)
        self.assertEqual(sent, ["api.amazon.com", "cde-ta-g7g.amazon.com"])

    def test_redirect_never_followed_even_to_allowed_host(self):
        for target in ["https://evil.test/", "https://api.amazon.com/next", "http://api.amazon.com/"]:
            sent = []
            with patch("kindl.client.httpx.HTTPTransport", return_value=httpx.MockTransport(
                    lambda req: sent.append(req) or httpx.Response(302, headers={"Location": target}))):
                with AmazonDeviceClient() as client:
                    with self.assertRaisesRegex(RuntimeError, "blocked a redirect"):
                        client.http.get("https://api.amazon.com/auth/token")
            self.assertEqual(len(sent), 1)

    def test_private_credentials_from_first_write_with_permissive_umask(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/"private"/"config.json"
            replace = Path.replace
            observed = []
            def inspect(source, target):
                observed.append(stat.S_IMODE(source.stat().st_mode))
                self.assertEqual(json.loads(source.read_text()), {"token": "SYNTHETIC"})
                return replace(source, target)
            old = os.umask(0)
            try:
                with patch.object(Path, "replace", inspect):
                    _write_private_json(path, {"token": "SYNTHETIC"})
            finally: os.umask(old)
            self.assertEqual(observed, [0o600])
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_public_or_symlink_credential_directory_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); public=root/"public"; public.mkdir(mode=0o755); public.chmod(0o755)
            with self.assertRaisesRegex(RuntimeError, "private"):
                _write_private_json(public/"config.json", {})
            link=root/"link"; link.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, "private"):
                _write_private_json(link/"config.json", {})
            self.assertFalse((public/"config.json").exists())

    def test_callback_uses_hidden_prompt_and_refuses_non_tty(self):
        out=io.StringIO()
        with patch("kindl.cli.sys.stdin.isatty", return_value=True), \
                patch("kindl.cli.getpass.getpass", return_value=" SYNTHETIC_CALLBACK ") as prompt, \
                patch("kindl.cli.os.open", return_value=999), \
                patch("termios.tcgetattr", return_value=[0,0,0,0,0,0,[0]*32]), \
                patch("termios.tcsetattr"), patch("kindl.cli.os.close"), \
                contextlib.redirect_stdout(out):
            self.assertEqual(_prompt_callback(), "SYNTHETIC_CALLBACK")
            prompt.assert_called_once_with("Final URL (hidden): ")
        self.assertNotIn("SYNTHETIC_CALLBACK", out.getvalue())
        with patch("kindl.cli.sys.stdin.isatty", return_value=False):
            with self.assertRaises(click.ClickException): _prompt_callback()


    def run_callback_pty(self, interrupt=False):
        # A fresh controlling PTY exercises real getpass and macOS line discipline.
        script = """
import hashlib, os, sys, termios
from kindl.cli import _prompt_callback
before = termios.tcgetattr(0)
try:
    value = _prompt_callback()
    print('RESULT', len(value), hashlib.sha256(value.encode()).hexdigest(), flush=True)
except KeyboardInterrupt:
    print('INTERRUPTED', flush=True)
finally:
    after = termios.tcgetattr(0)
    # macOS PENDIN is kernel queue state, set when canonical mode resumes.
    # It is not a configurable mode; compare every other flag and control byte.
    before[3] &= ~getattr(termios, 'PENDIN', 0)
    after[3] &= ~getattr(termios, 'PENDIN', 0)
    print('RESTORED', after == before, flush=True)
"""
        pid, master = pty.fork()
        if pid == 0:
            os.execv(sys.executable, [sys.executable, '-c', script])
        output = b''
        payload = (b'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' * 112)[:4000]
        deadline = time.monotonic() + 10
        sent = False
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try: chunk = os.read(master, 8192)
                    except OSError as error:
                        if error.errno == errno.EIO: break
                        raise
                    if not chunk: break
                    output += chunk
                if not sent and b'Final URL (hidden): ' in output:
                    flags = termios.tcgetattr(master)[3]
                    self.assertFalse(flags & (termios.ICANON | termios.ECHO | termios.ECHONL))
                    data = b'\x03' if interrupt else payload + b'\n'
                    while data:
                        data = data[os.write(master, data):]
                    sent = True
            else:
                self.fail('Hidden callback PTY did not finish within 10 seconds')
            _, status = os.waitpid(pid, 0)
            pid = None
            self.assertEqual(os.waitstatus_to_exitcode(status), 0, output.decode(errors="replace")[:1500])
            self.assertTrue(sent)
            self.assertNotIn(payload[:72], output)
            marker = b'INTERRUPTED' if interrupt else b'RESULT'
            self.assertEqual(output.split(marker, 1)[0].replace(b'\r', b'').replace(b'\n', b''), b'Final URL (hidden): ')
            self.assertIn(b'RESTORED True', output)
            if interrupt:
                self.assertIn(b'INTERRUPTED', output)
            else:
                self.assertIn(('RESULT 4000 ' + hashlib.sha256(payload).hexdigest()).encode(), output)
        finally:
            os.close(master)
            if pid is not None:
                try: os.kill(pid, signal.SIGKILL)
                except ProcessLookupError: pass
                os.waitpid(pid, 0)

    def test_long_hidden_callback_pty_preserves_all_4000_chars_and_restores_terminal(self):
        self.run_callback_pty()

    def test_hidden_callback_interrupt_restores_terminal(self):
        self.run_callback_pty(interrupt=True)


if __name__ == "__main__": unittest.main(verbosity=2)
