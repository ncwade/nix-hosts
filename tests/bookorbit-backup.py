#!/usr/bin/env python3
"""Exercise backup failure handling without production paths or services."""
import os, pathlib, re, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['TEST_ROOT'])
with (root/'events').open('a') as f: f.write(name+' '+' '.join(args)+'\n')
fail = os.environ.get('FAIL_AT', '')
if name == 'systemctl':
    action = args[0]; service = args[-1].removesuffix('.service'); flag = root/('active-'+service)
    if action == 'is-active': sys.exit(0 if flag.exists() else 3)
    if action == 'stop': flag.unlink(missing_ok=True)
    if action == 'start': flag.touch()
elif name == 'podman':
    if fail == 'dump': sys.exit(1)
    print('-- PostgreSQL database cluster dump complete')
elif name == 'bookorbit-restic':
    if fail == 'network': sys.exit(1)
elif name == 'rsync':
    if fail == 'copy' and (root/'events').read_text().count('rsync ') == 3: sys.exit(1)
'''
class BackupTest(unittest.TestCase):
    def run_case(self, fail='', active=True):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp); bindir=root/'bin'; bindir.mkdir()
            for name in ('systemctl','podman','bookorbit-restic','rsync','flock'):
                p=bindir/name; p.write_text(MOCK); p.chmod(0o755)
            def rewrite(text):
                paths = ('/var/lib/tsidp','/var/lib/bookorbit-backup','/var/lib/bookorbit-tailnet','/var/lib/bookorbit-alerts','/var/lib/bookorbit-connector-health','/var/lib/bookorbit','/srv/books','/etc/bookorbit','/run/bookorbit-backup','/run/lock/bookorbit-media.lock','/var/lib/libation','/var/lib/bookorbit-kindle')
                return re.sub('|'.join(map(re.escape, paths)), lambda m: str(root/m.group().lstrip('/')), text)
            resume=bindir/'bookorbit-backup-resume'
            resume.write_text('#!/usr/bin/env bash\nset -euo pipefail\n'+rewrite((ROOT/'modules/nixos/bookorbit/resume.sh').read_text()));resume.chmod(0o755)
            for p in ('var/lib/tsidp','var/lib/bookorbit-tailnet','var/lib/bookorbit/app','var/lib/bookorbit/secrets','srv/books','etc/bookorbit','run/lock','var/lib/libation','var/lib/bookorbit-kindle','var/lib/bookorbit-alerts','var/lib/bookorbit-connector-health'):
                (root/p).mkdir(parents=True, exist_ok=True)
            for service in ('tsidp','podman-bookorbit','bookorbit-tailnet','bookorbit-tailnet-serve'):
                if active: (root/('active-'+service)).touch()
            script=root/'backup.sh';script.write_text(rewrite((ROOT/'modules/nixos/bookorbit/backup.sh').read_text()))
            result=subprocess.run(['bash',str(script)], env={**os.environ, 'PATH':str(bindir)+':'+os.environ['PATH'], 'TEST_ROOT':tmp, 'FAIL_AT':fail}, capture_output=True,text=True)
            events=(root/'events').read_text()
            self.assertEqual(result.returncode == 0, not bool(fail), result.stderr)
            for service in ('tsidp','podman-bookorbit','bookorbit-tailnet','bookorbit-tailnet-serve'):
                self.assertEqual((root/('active-'+service)).exists(), active, events)
            if fail in ('dump','copy'): self.assertNotIn('bookorbit-restic backup', events)
            if fail == 'network': self.assertNotIn('bookorbit-restic forget',events)
            if active and fail not in ('dump','copy'):
                self.assertLess(events.index('systemctl start podman-bookorbit'), events.index('bookorbit-restic backup'))
                self.assertLess(events.index('systemctl start bookorbit-tailnet.service'), events.index('systemctl start bookorbit-tailnet-serve.service'))
                self.assertLess(events.index('systemctl start bookorbit-tailnet-serve.service'), events.index('bookorbit-restic backup'))
            self.assertEqual((root/'var/lib/bookorbit-backup/last-success').exists(),not bool(fail))
            if not fail:
                self.assertLess(events.index('flock 9'), events.index('rsync '))
                self.assertLess(events.index('libation/'), events.index('flock -u 9'))
                self.assertLess(events.index('bookorbit-kindle/'), events.index('flock -u 9'))
                self.assertLess(events.index('bookorbit-alerts/'), events.index('flock -u 7'))
                self.assertLess(events.index('flock -u 9'), events.index('bookorbit-restic backup'))
    def test_success(self): self.run_case()
    def test_dump_failure_resumes_services(self): self.run_case('dump')
    def test_copy_failure_resumes_services(self): self.run_case('copy')
    def test_network_failure_happens_after_resume(self): self.run_case('network')
    def test_inactive_services_remain_inactive(self): self.run_case(active=False)
if __name__ == '__main__': unittest.main()
