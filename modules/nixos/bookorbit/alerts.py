"""Monitor completed connector runs; retain unsent events for retry."""
import argparse
import base64
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


def publish(event, credentials, url):
    name = {'kindle-sync': 'Kindle downloads', 'kindle': 'Kindle import'}.get(event['connector'], event['connector'].capitalize())
    failed = event['kind'] == 'failure'
    message = (f'{name} connector failed on Tycho. {event["reason"]}' if failed else
               f'{name} connector recovered on Tycho after a completed successful run.')
    payload = {'topic': 'bookorbit', 'title': f'BookOrbit: {name} {event["kind"]}',
               'message': message, 'priority': 4 if failed else 3,
               'tags': ['warning'] if failed else ['white_check_mark']}
    password = credentials['bookorbit-publisher']
    authorization = base64.b64encode(f'bookorbit-publisher:{password}'.encode()).decode()
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), headers={
        'Authorization': f'Basic {authorization}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=10) as response:
        if json.load(response).get('event') != 'message':
            raise RuntimeError('ntfy did not confirm message acceptance')


def flush(state, path, send):
    while state.get('pending'):
        send(state['pending'][0])
        state['pending'].pop(0)
        save(path, state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test-event', choices=['failure', 'recovery'])
    args = parser.parse_args()
    os.umask(0o077)
    root = Path('/var/lib/bookorbit-alerts')
    with (root / 'check.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / 'state.json'
        state = json.loads(path.read_text()) if path.exists() else {'incidents': {}, 'pending': []}
        credentials = json.loads((root / 'credentials.json').read_text())
        if args.test_event:
            state['pending'].append({'connector': 'test', 'kind': args.test_event,
                                     'reason': 'Intentional notification delivery test.', 'time': time.time()})
        else:
            for connector, marker in CONNECTORS.items():
                failure, success_time = inspect(connector, marker)
                transition(state, connector, failure, success_time, time.time())
        save(path, state)
        flush(state, path, lambda event: publish(event, credentials, 'http://127.0.0.1:2586/'))


if __name__ == '__main__':
    main()
