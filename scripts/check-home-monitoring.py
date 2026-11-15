#!/usr/bin/env python3
"""Run as root on Tycho. Never print credentials or response bodies on errors."""
import base64
import csv
import io
import json
from pathlib import Path
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

root = Path('/var/lib/home-monitoring')
secrets = root / 'secrets'

def request(url, data=None, token=None, basic=None, content_type='application/json'):
    headers = {'Content-Type': content_type}
    if token:
        headers['Authorization'] = 'Token ' + token
    if basic:
        headers['Authorization'] = 'Basic ' + base64.b64encode(basic.encode()).decode()
    if isinstance(data, dict): data = json.dumps(data).encode()
    try:
        with urlopen(Request(url, data=data, headers=headers), timeout=30) as r:
            return r.status, r.read()
    except HTTPError as e:
        return e.code, b''

read = (secrets / 'grafana-read-token').read_text().strip()
write = (secrets / 'ha-write-token').read_text().strip()
operator = (secrets / 'influx-operator-token').read_text().strip()
basic = 'admin:' + (secrets / 'grafana-admin-password').read_text().strip()
for name, url in [('Home Assistant', 'http://127.0.0.1:8123/'), ('InfluxDB', 'http://127.0.0.1:8086/health'), ('Grafana', 'http://127.0.0.1:3002/api/health')]:
    code, _ = request(url)
    assert code == 200, (name, code)
    print(name + ': HTTP healthy')
code, body = request('http://127.0.0.1:8086/api/v2/buckets?name=home_history', token=operator)
assert code == 200
bucket = json.loads(body)['buckets'][0]
assert bucket['retentionRules'][0]['everySeconds'] == 1825 * 86400
print('Retention: 1825 days verified')
query = 'from(bucket: "home_history") |> range(start: -5m) |> filter(fn: (r) => r._measurement == "home_state" and r.entity_id == "tcc_availability" and r._field == "state") |> last()'
code, body = request('http://127.0.0.1:8086/api/v2/query?org=home', {'query': query}, read)
assert code == 200, ('read query', code)
rows = list(csv.DictReader(line for line in io.StringIO(body.decode()) if line.strip() and not line.startswith('#')))
assert rows, 'No Home Assistant availability snapshots received in last 5 minutes'
print('Home Assistant → InfluxDB: recent availability snapshot verified (' + rows[-1]['_value'] + ')')
code, _ = request('http://127.0.0.1:8086/api/v2/query?org=home', {'query': query}, write)
assert code in (401,403,404), ('writer read unexpectedly allowed', code)
code, _ = request('http://127.0.0.1:8086/api/v2/write?org=home&bucket=home_history', b'monitoring_permission_probe value=1', read, content_type='text/plain')
assert code in (401,403), ('reader write unexpectedly allowed', code)
code, body = request('http://127.0.0.1:8086/api/v2/authorizations', token=operator)
assert code == 200
authorizations = json.loads(body)['authorizations']
for name, action in [('ha-write-token','write'), ('grafana-read-token','read')]:
    found = [a for a in authorizations if a.get('description') == 'home-monitoring ' + name and a.get('status') == 'active']
    assert len(found) == 1
    permissions = found[0]['permissions']
    assert len(permissions) == 1
    assert permissions[0]['action'] == action
    assert permissions[0]['resource']['type'] == 'buckets'
    assert permissions[0]['resource']['id'] == bucket['id']
print('Least privilege: Grafana writes denied; Home Assistant reads denied')
code, body = request('http://127.0.0.1:3002/api/dashboards/uid/tycho-tcc', basic=basic)
assert code == 200, ('dashboard',code)
dashboard = json.loads(body)['dashboard']
assert dashboard['timezone'] == 'America/Chicago'
queries = 0
for panel in dashboard['panels']:
    for target in panel.get('targets', []):
        payload = {'from': str(int((time.time()-86400)*1000)), 'to': str(int(time.time()*1000)),
                   'queries': [{**target, 'intervalMs':30000, 'maxDataPoints':3000}]}
        code, body = request('http://127.0.0.1:3002/api/ds/query', payload, basic=basic)
        assert code == 200, ('Grafana panel query HTTP failure', panel['title'], code)
        result = json.loads(body)
        assert not any(v.get('error') or v.get('status',200) >= 400 for v in result.get('results', {}).values()), ('Grafana query failed', panel['title'])
        if panel['type'] == 'stat' and 'r._field == "state"' in target['query']:
            assert panel['options']['reduceOptions']['fields'] == '/^Value$/', ('String card excludes text fields', panel['title'])
            values = [value for response in result['results'].values()
                      for frame in response.get('frames', [])
                      for field, column in zip(frame['schema']['fields'], frame['data']['values'])
                      if field['name'] == 'Value' and field['type'] == 'string'
                      for value in column if value is not None]
            assert values, ('No current text status data', panel['title'])
        queries += 1
print(f'Grafana: {queries} queries passed, including populated text status cards; optional missing readings remain unknown')
# Registry metadata only; do not read config_entries, which contains credentials.
registry = root / 'home-assistant/.storage/core.entity_registry'
if registry.exists():
    entities = json.loads(registry.read_text())['data']['entities']
    found = [e for e in entities if e.get('platform') == 'honeywell']
    print('Discovered Honeywell entities: ' + str(len(found)))
    for entity in found:
        print(json.dumps({k: entity.get(k) for k in ('entity_id','disabled_by','original_name')}))
