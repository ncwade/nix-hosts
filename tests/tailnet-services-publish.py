#!/usr/bin/env python3
"""Test the rendered publisher: fail closed on identity and map every endpoint."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(sys.argv.pop(1)).read_text() if len(sys.argv) > 1 else None
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['TEST_ROOT'])
args = sys.argv[1:]
with (root / 'events').open('a') as f: f.write(json.dumps(args) + '\n')
if args[1:3] == ['status', '--json']:
    print(os.environ['TS_STATUS'])
elif os.environ.get('FAIL_SERVICE') and os.environ['FAIL_SERVICE'] in args:
    sys.exit(1)
'''


@unittest.skipUnless(SCRIPT, 'pass the Nix-rendered publication script as the first argument')
class PublisherTest(unittest.TestCase):
    def run_case(self, status, fail=''):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'tailscale').write_text(MOCK)
            (root / 'tailscale').chmod(0o755)
            (root / 'sleep').write_text('#!/bin/sh\nexit 0\n')
            (root / 'sleep').chmod(0o755)
            script = root / 'publish.sh'
            # NixOS's service wrapper enables errexit; preserve that in the test.
            script.write_text('set -euo pipefail\n' + SCRIPT)
            result = subprocess.run(['bash', str(script)], capture_output=True, text=True,
                                    env={**os.environ, 'PATH': f'{root}:' + os.environ['PATH'],
                                         'TEST_ROOT': tmp, 'TS_STATUS': json.dumps(status),
                                         'FAIL_SERVICE': fail})
            events = [json.loads(line) for line in (root / 'events').read_text().splitlines()]
            for args in events:
                self.assertEqual(args[0], '--socket=/run/tailnet-services/tailscaled.sock')
            return result.returncode, events

    def test_all_endpoints(self):
        code, events = self.run_case({'BackendState': 'Running', 'Self': {'Tags': ['tag:tycho-services']}})
        self.assertEqual(code, 0)
        endpoints = [args[1:] for args in events if args[1] == 'serve']
        expected = []
        for app, port, redirect in [('bookorbit', 3000, 3001), ('grafana', 3002, 3003),
                                    ('home-assistant', 8123, 8124), ('llm', 8080, 8081)]:
            expected += [['serve', f'--service=svc:{app}', '--https=443', f'http://127.0.0.1:{port}'],
                         ['serve', f'--service=svc:{app}', '--http=80', f'http://127.0.0.1:{redirect}']]
        self.assertEqual(endpoints, expected)

    def test_user_owned_or_wrong_tag_does_not_publish(self):
        for tags in [None, [], ['tag:unrelated']]:
            code, events = self.run_case({'BackendState': 'Running', 'Self': {'Tags': tags}})
            self.assertNotEqual(code, 0)
            self.assertEqual(len(events), 1)

    def test_expired_login_does_not_publish(self):
        code, events = self.run_case({'BackendState': 'NeedsLogin', 'Self': {'Tags': ['tag:tycho-services']}})
        self.assertNotEqual(code, 0)
        self.assertEqual(len(events), 1)

    def test_failed_mapping_is_observable(self):
        code, events = self.run_case({'BackendState': 'Running', 'Self': {'Tags': ['tag:tycho-services']}},
                                    '--service=svc:grafana')
        self.assertNotEqual(code, 0)
        self.assertFalse(any('--service=svc:home-assistant' in args for args in events))


if __name__ == '__main__':
    unittest.main()
