"""Monitor completed connector runs and export latched incident health to Grafana."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

CONNECTORS = {
    'audible': Path('/var/lib/libation/last-success'),
    'kindle': Path('/var/lib/bookorbit-connector-health/kindle-success'),
    'kindle-sync': Path('/var/lib/bookorbit-kindle/last-success'),
}


def save(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value) + '\n')
    temporary.replace(path)


def transition(state, connector, failure, success_time, now):
    incident = state.setdefault('incidents', {}).get(connector)
    event = None
    if failure and incident is None:
        state['incidents'][connector] = {'since': now}
        event = {'connector': connector, 'kind': 'failure', 'reason': failure, 'time': now}
    elif not failure and incident and success_time > incident['since']:
        del state['incidents'][connector]
        event = {'connector': connector, 'kind': 'recovery', 'time': now}
    if event:
        state.setdefault('pending', []).append(event)


def inspect(connector, marker):
    result = subprocess.run(
        ['systemctl', 'show', f'bookorbit-{connector}.service',
         '--property=LoadState,ActiveState,Result,ConditionResult'],
        check=True, capture_output=True, text=True)
    properties = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if properties.get('LoadState') != 'loaded':
        return 'Service is missing.', 0
    if properties.get('ActiveState') in ('activating', 'active', 'deactivating'):
        return None, 0  # An in-progress run cannot establish recovery.
    if properties.get('ConditionResult') == 'no':
        return 'Required connector credentials are missing.', 0
    if properties.get('Result') != 'success':
        return 'Connector run failed; inspect its service journal on Tycho.', 0
    return None, marker.stat().st_mtime if marker.exists() else 0


def publish_health(state, token_file, url='http://127.0.0.1:8086/api/v2/write?org=home&bucket=home_history&precision=s'):
    # A running job or lock deferral cannot clear a latched incident. Preserve
    # failures that recovered while InfluxDB was unreachable for one accepted
    # sample, so the next healthy sample cannot erase an unseen failure.
    failed = set(state.get('incidents', {})) | {
        event['connector'] for event in state.get('pending', []) if event['kind'] == 'failure'
    }
    timestamp = int(time.time())
    lines = [f'bookorbit_health,host=tycho,connector={name} failed={int(name in failed)}i {timestamp}'
             for name in CONNECTORS]
    request = urllib.request.Request(url, data=('\n'.join(lines) + '\n').encode(), headers={
        'Authorization': 'Token ' + Path(token_file).read_text().strip(),
        'Content-Type': 'text/plain'})
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 204:
            raise RuntimeError('InfluxDB did not confirm health acceptance')


def deliver(state, path):
    token_file = os.environ.get('BOOKORBIT_INFLUX_TOKEN_FILE')
    if not token_file:
        raise RuntimeError('The Grafana health exporter credential is not configured')
    publish_health(state, token_file)
    # Preserve existing incidents through the transition. Clear legacy events
    # only after InfluxDB accepts health; the next timer run retries failures.
    state['pending'] = []
    save(path, state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    os.umask(0o077)
    root = Path('/var/lib/bookorbit-alerts')
    with (root / 'check.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / 'state.json'
        state = json.loads(path.read_text()) if path.exists() else {'incidents': {}, 'pending': []}
        for connector, marker in CONNECTORS.items():
            failure, success_time = inspect(connector, marker)
            transition(state, connector, failure, success_time, time.time())
        save(path, state)
        deliver(state, path)


if __name__ == '__main__':
    main()
