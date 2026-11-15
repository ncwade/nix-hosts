#!/usr/bin/env python3
"""Backup must tolerate retired app nodes and resume only previously active units."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import os, sys
from pathlib import Path
root = Path(os.environ['TEST_ROOT'])
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'events').open('a') as f:
    f.write(name + ' ' + ' '.join(args) + '\n')
if name == 'id':
    print('0')
elif name == 'systemctl':
    action = args[0]
    units = [a for a in args[1:] if not a.startswith('-')]
    for unit in units:
        if action == 'is-active':
            sys.exit(0 if (root / ('active-' + unit)).exists() else 3)
        if not (root / ('known-' + unit)).exists():
            sys.exit(5)
        if action == 'stop':
            (root / ('active-' + unit)).unlink(missing_ok=True)
        elif action == 'start':
            (root / ('active-' + unit)).touch()
elif name == 'rsync' and os.environ.get('FAIL_COPY') == 'yes':
    if (root / 'events').read_text().count('rsync ') == 2:
        sys.exit(1)
'''


class MonitoringBackupTest(unittest.TestCase):
    def run_case(self, legacy, fail=False, inactive=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bindir = root / 'bin'
            bindir.mkdir()
            for name in ('id', 'systemctl', 'rsync', 'flock', 'docker', 'bookorbit-restic'):
                path = bindir / name
                path.write_text(MOCK)
                path.chmod(0o755)
            units = ['home-monitoring']
            if legacy:
                units += [f'{app}-tailnet{suffix}' for app in ('home-assistant', 'grafana')
                          for suffix in ('', '-serve')]
            for unit in units:
                (root / ('known-' + unit)).touch()
                if not inactive:
                    (root / ('active-' + unit)).touch()
            # The shared host must remain up throughout the app's cold copy.
            (root / 'active-tailnet-services').touch()
            (root / 'hostname').write_text('tycho\n')
            script = (ROOT / 'scripts/backup-home-monitoring.sh').read_text()
            for old, new in {
                '/proc/sys/kernel/hostname': str(root / 'hostname'),
                '/run/lock/home-monitoring-deploy.lock': str(root / 'lock'),
                '/var/lib/home-monitoring-backup/staging': str(root / 'staging'),
                '/run/current-system/sw/bin/bookorbit-restic': str(bindir / 'bookorbit-restic'),
            }.items():
                script = script.replace(old, new)
            path = root / 'backup.sh'
            path.write_text(script)
            result = subprocess.run(['bash', str(path)], capture_output=True, text=True,
                                    env={**os.environ, 'PATH': f'{bindir}:' + os.environ['PATH'],
                                         'TEST_ROOT': tmp, 'FAIL_COPY': 'yes' if fail else 'no'})
            self.assertEqual(result.returncode == 0, not fail, result.stderr)
            events = (root / 'events').read_text()
            for unit in units:
                self.assertEqual((root / ('active-' + unit)).exists(), not inactive)
            self.assertTrue((root / 'active-tailnet-services').exists())
            self.assertNotIn('systemctl stop tailnet-services', events)
            if not legacy:
                for line in events.splitlines():
                    if line.startswith(('systemctl stop', 'systemctl start')):
                        self.assertNotIn('-tailnet', line)
            if fail:
                self.assertNotIn('bookorbit-restic backup', events)
            elif not inactive:
                self.assertLess(events.index('systemctl start'), events.index('bookorbit-restic backup'))

    def test_legacy(self): self.run_case(True)
    def test_services(self): self.run_case(False)
    def test_copy_failure_resumes_stack(self): self.run_case(False, fail=True)
    def test_inactive_stack_stays_inactive(self): self.run_case(False, inactive=True)


if __name__ == '__main__':
    unittest.main()
