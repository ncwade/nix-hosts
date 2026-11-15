"""Initialize only this stack. Never print credentials or API response bodies."""
import json
import os
from pathlib import Path
import secrets
import time
from urllib.error import URLError
from urllib.request import Request, urlopen

ROOT = Path('/var/lib/home-monitoring')
os.umask(0o077)
for name in ('secrets', 'home-assistant/packages', 'influxdb', 'influx-config', 'grafana'):
    (ROOT / name).mkdir(parents=True, exist_ok=True)
os.chown(ROOT / 'grafana', 472, 472)
os.chmod(ROOT / 'grafana', 0o750)

def secret(name):
    p = ROOT / 'secrets' / name
    if not p.exists():
        p.write_text(secrets.token_hex(32))
    return p.read_text().strip()

admin = secret('influx-operator-token')
password = secret('influx-admin-password')
grafana_password = secret('grafana-admin-password')

def api(path, payload=None, token=admin):
    headers = {'Content-Type': 'application/json', 'Authorization': 'Token ' + token}
    body = None if payload is None else json.dumps(payload).encode()
    with urlopen(Request('http://127.0.0.1:8086' + path, data=body, headers=headers), timeout=10) as r:
        return json.load(r)

for attempt in range(90):
    try:
        setup = api('/api/v2/setup')
        break
    except (URLError, TimeoutError):
        time.sleep(2)
else:
    raise SystemExit('InfluxDB did not become ready; inspect service health.')

if setup['allowed']:
    api('/api/v2/setup', {'username': 'admin', 'password': password, 'token': admin,
                         'org': 'home', 'bucket': 'home_history',
                         'retentionPeriodSeconds': 5 * 365 * 86400})
org = api('/api/v2/orgs?org=home')['orgs'][0]['id']
bucket = api('/api/v2/buckets?orgID=' + org + '&name=home_history')['buckets'][0]['id']
for name, action in (('ha-write-token', 'write'), ('grafana-read-token', 'read'), ('bookorbit-write-token', 'write')):
    p = ROOT / 'secrets' / name
    if not p.exists():
        result = api('/api/v2/authorizations', {
            'orgID': org, 'description': 'home-monitoring ' + name,
            'permissions': [{'action': action, 'resource': {'type': 'buckets', 'id': bucket, 'orgID': org}}]})
        p.write_text(result['token'])
(ROOT / 'home-assistant/secrets.yaml').write_text(
    'influx_write_token: ' + json.dumps((ROOT / 'secrets/ha-write-token').read_text()) + '\n')
(ROOT / 'secrets/grafana.env').write_text(
    'GF_SECURITY_ADMIN_USER=admin\nGF_SECURITY_ADMIN_PASSWORD=' + grafana_password + '\n'
    'INFLUX_READ_TOKEN=' + (ROOT / 'secrets/grafana-read-token').read_text() + '\n')
print('InfluxDB initialized: 1825-day retention; separate write-only and read-only bucket tokens.')
