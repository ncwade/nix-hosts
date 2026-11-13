#!/usr/bin/env python3
"""Check that scan failure and low space cannot start new downloads."""
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MOCK = '''#!/usr/bin/env python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['EVENTS'], 'a') as f: f.write(name + ' ' + ' '.join(args) + '\\n')
if name == 'df': print('Avail\\n' + ('1' if os.environ.get('LOW_SPACE') else '900000000000'))
if name == 'du': print('1000000\\t/books')
if name == 'bookorbit-audible-cli' and args[0] == os.environ.get('FAIL_AT'): sys.exit(1)
if name == 'bookorbit-audible-cli' and args[0] == 'export':
    (pathlib.Path(os.environ['EVENTS']).parent / 'var/lib/libation/inventory.json').write_text('[]')
'''

class AudibleTest(unittest.TestCase):
    def run_case(self, fail='', low=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            bindir = root / 'bin'
            bindir.mkdir()
            for name in ('flock', 'install', 'df', 'du', 'bookorbit-audible-cli'):
                p = bindir / name
                p.write_text(MOCK)
                p.chmod(0o755)
            (root / 'var/lib/libation').mkdir(parents=True)
            (root / 'run/lock').mkdir(parents=True)
            script = (ROOT / 'modules/nixos/bookorbit/audible.sh').read_text()
            script = re.sub(r'/run/lock/bookorbit-media.lock|/var/lib/libation',
                            lambda m: str(root / m.group().lstrip('/')), script)
            result = subprocess.run(['bash', '-c', script], capture_output=True, text=True,
                                    env={**os.environ, 'PATH': str(bindir) + ':' + os.environ['PATH'],
                                         'EVENTS': str(root / 'events'), 'FAIL_AT': fail,
                                         'LOW_SPACE': '1' if low else '',
                                         'AUDIBLE_HEALTH_CHECK': str(ROOT / 'modules/nixos/bookorbit/audible-health.py')})
            events = (root / 'events').read_text()
            self.assertEqual(result.returncode == 0, not (fail or low), result.stderr)
            self.assertEqual((root / 'var/lib/libation/last-success').exists(), not (fail or low))
            if fail == 'scan' or low:
                self.assertNotIn('bookorbit-audible-cli liberate', events)
            if low:
                self.assertNotIn('bookorbit-audible-cli scan', events)
            if not (fail or low):
                self.assertLess(events.index('flock 9'), events.index('bookorbit-audible-cli scan'))
                self.assertLess(events.index('set-status'), events.index('liberate'))

    def test_success(self): self.run_case()
    def test_failed_scan_does_not_download(self): self.run_case('scan')
    def test_failed_download_does_not_record_success(self): self.run_case('liberate')
    def test_low_space_does_not_download(self): self.run_case(low=True)

if __name__ == '__main__':
    unittest.main()
