#!/usr/bin/env python3
"""Retire the transitional ntfy route after live Grafana phone acceptance."""
import argparse
import base64
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import time
from urllib.request import Request, urlopen


PHASE_ONE = {
    'modules/nixos/bookorbit/alerts.py': 'f22675af7f1b1e1c2066a787d425319b721b44b947bf0643ae6a1a233bbdccd1',
    'modules/nixos/bookorbit/alerts.nix': '0bbb593c2edbcc127121cdf07789775f689b88f5f1e3e8d6a7c172153fb06e5c',
}
RULES = {'bookorbit-audible', 'bookorbit-kindle', 'bookorbit-kindle-sync'}


def run(*args, cwd=None):
    subprocess.run(args, check=True, cwd=cwd)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def verify_grafana():
    root = Path('/var/lib/home-monitoring')
    target = (root / 'secrets/iphone-notify-service').read_text().strip()
    package = json.loads((root / 'home-assistant/packages/grafana_alerts.yaml').read_text())
    if package['automation'][0]['actions'][0]['repeat']['sequence'][0]['action'] != target:
        raise RuntimeError('Home Assistant does not target the selected phone')
    password = (root / 'secrets/grafana-admin-password').read_text().strip()
    auth = base64.b64encode(('admin:' + password).encode()).decode()

    def api(path, data=None):
        request = Request('http://127.0.0.1:3002' + path,
                          data=json.dumps(data).encode() if data is not None else None,
                          headers={'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'})
        with urlopen(request, timeout=30) as response:
            return json.load(response)

    rules = [r for r in api('/api/v1/provisioning/alert-rules') if r['uid'] in RULES]
    if {r['uid'] for r in rules} != RULES:
        raise RuntimeError('Expected three provisioned connector rules')
    for rule in rules:
        if rule['isPaused'] or rule['notification_settings']['receiver'] != 'home-assistant-iphone':
            raise RuntimeError('Connector rule is paused or uses another receiver')
        result = api('/api/ds/query', {
            'from': str(int((time.time() - 300) * 1000)), 'to': str(int(time.time() * 1000)),
            'queries': [rule['data'][0]['model']],
        })['results']['A']
        if result.get('error') or not any(
                values for frame in result.get('frames', []) for values in frame.get('data', {}).get('values', [])):
            raise RuntimeError('A connector health query failed or has no samples')
    for service in ('home-monitoring', 'podman-bookorbit', 'podman-bookorbit-db', 'tsidp', 'rex-login-server'):
        run('systemctl', 'is-active', '--quiet', service)
    with urlopen('http://127.0.0.1:8123/', timeout=10) as response:
        if response.status != 200:
            raise RuntimeError('Home Assistant is unavailable')


def check_retired():
    for service in ('ntfy-sh', 'bookorbit-alert-serve', 'bookorbit-alert-secrets'):
        if output('systemctl', 'show', service, '-p', 'ActiveState', '--value') in ('active', 'activating'):
            raise RuntimeError(service + ' is still active')
    with socket.socket() as connection:
        connection.settimeout(2)
        if connection.connect_ex(('127.0.0.1', 2586)) == 0:
            raise RuntimeError('The old ntfy listener is still reachable')
    serve = json.loads(output('tailscale', 'serve', 'status', '--json'))
    if '8443' in serve.get('TCP', {}) or any(k.endswith(':8443') for k in serve.get('Web', {})):
        raise RuntimeError('The old ntfy Tailscale address is still configured')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phone-delivery-confirmed', action='store_true', required=True,
                        help='Confirm receipt of both firing and resolved messages through Grafana')
    parser.parse_args()
    if os.geteuid() != 0 or Path('/proc/sys/kernel/hostname').read_text().strip() != 'tycho':
        raise SystemExit('Run through sudo on Tycho')
    os.umask(0o077)
    bundle = Path(__file__).resolve().parents[1]
    current = Path('/etc/nixos')
    with open('/run/lock/home-monitoring-deploy.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        verify_grafana()
        for name, digest in PHASE_ONE.items():
            actual = hashlib.sha256((current / name).read_bytes()).hexdigest()
            final = hashlib.sha256((bundle / name).read_bytes()).hexdigest()
            if actual not in (digest, final):
                raise RuntimeError('Unexpected live source; refusing to overwrite ' + name)
        if all((current / p).read_bytes() == (bundle / p).read_bytes() for p in PHASE_ONE):
            check_retired()
            print('ntfy is already retired; Grafana health queries passed.')
            return
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        work = Path('/var/lib/nixos-source-backups') / ('ntfy-retirement-' + stamp)
        work.mkdir(parents=True)
        previous = Path('/run/current-system').resolve()
        (work / 'system').write_text(str(previous) + '\n')
        shutil.copytree(current, work / 'previous-source', symlinks=True)
        candidate = work / 'candidate'
        shutil.copytree(current, candidate, symlinks=True)
        for name in PHASE_ONE:
            shutil.copy2(bundle / name, candidate / name)
        obsolete = 'modules/nixos/bookorbit/alert-secrets.py'
        (candidate / obsolete).unlink(missing_ok=True)
        flake = 'path:' + str(candidate) + '#tycho'
        run('nixos-rebuild', 'build', '--flake', flake, '--no-write-lock-file', cwd=work)
        for unit in ('bookorbit-kindle-sync', 'bookorbit-kindle', 'bookorbit-audible', 'bookorbit-backup'):
            if output('systemctl', 'show', unit, '-p', 'ActiveState', '--value') in ('active', 'activating'):
                name = 'etc/systemd/system/' + unit + '.service'
                if (previous / name).read_bytes() != (work / 'result' / name).read_bytes():
                    raise RuntimeError('Active ' + unit + ' would change; retry after it finishes')
        try:
            run('nixos-rebuild', 'test', '--flake', flake, '--no-write-lock-file', cwd=work)
            run('systemctl', 'start', 'bookorbit-alert-check.service')
            verify_grafana()
            check_retired()
            run('nixos-rebuild', 'switch', '--flake', flake, '--no-write-lock-file', cwd=work)
            for name in PHASE_ONE:
                shutil.copy2(candidate / name, current / name)
            (current / obsolete).unlink(missing_ok=True)
        except BaseException:
            for name in (*PHASE_ONE, obsolete):
                saved = work / 'previous-source' / name
                if saved.exists():
                    shutil.copy2(saved, current / name)
            run('nix-env', '--profile', '/nix/var/nix/profiles/system', '--set', str(previous))
            run(str(previous / 'bin/switch-to-configuration'), 'switch')
            raise
        print('ntfy retired; Grafana alerting verified. Recovery copy: ' + str(work))
        print('Legacy credentials, cache, and incident state have not been deleted.')


if __name__ == '__main__':
    main()
