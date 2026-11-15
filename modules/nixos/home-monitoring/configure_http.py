"""Seed the pinned HA 2026.11 HTTP store while HA is stopped.

HA >=2026.8 imports YAML as an expiring five-minute trial. An unattended first
boot needs a stable listener before an owner exists to confirm a trial in the UI.
Only migrate our exact initial loopback/proxy trial; preserve other saved settings.
"""
from datetime import datetime, timezone
import json
import os
from pathlib import Path

os.umask(0o077)
p = Path('/var/lib/home-monitoring/home-assistant/.storage/http')
expected = {'server_host':['127.0.0.1'], 'server_port':8123,
            'use_x_forwarded_for':True, 'trusted_proxies':['127.0.0.1/32','::1/128']}
if p.exists():
    saved = json.loads(p.read_text())
    if saved['version'] != 3 or saved['minor_version'] != 1:
        raise SystemExit('HTTP storage version changed; review before provisioning.')
    data = saved['data']
    stable, pending = data['stable'], data['pending']
    if all(stable.get(k) == v for k,v in expected.items()):
        if pending is not None and any(pending.get(k) != v for k,v in expected.items()):
            raise SystemExit('Pending HTTP settings conflict with private listener; review in HA.')
        print('Home Assistant stable loopback/proxy configuration verified.')
        raise SystemExit(0)
    if pending is None or any(pending.get(k) != v for k,v in expected.items()):
        raise SystemExit('Existing HTTP settings differ; refusing to overwrite them.')
    backup = p.with_name('http.before-monitoring')
    if not backup.exists(): backup.write_text(p.read_text())
    stable = {**pending, 'error':None, 'error_message':None}
else:
    stable = {**expected, 'cors_allowed_origins':['https://cast.home-assistant.io'],
              'login_attempts_threshold':-1, 'ip_ban_enabled':True,
              'ssl_profile':'intermediate_v6', 'use_x_frame_options':True,
              'created_at':datetime.now(timezone.utc).isoformat(), 'error':None, 'error_message':None}
p.parent.mkdir(parents=True, exist_ok=True)
saved = {'version':3, 'minor_version':1, 'key':'http',
         'data':{'stable':stable, 'pending':None, 'yaml_migration_done':True}}
tmp = p.with_suffix('.tmp')
tmp.write_text(json.dumps(saved, indent=2)+'\n')
tmp.replace(p)
print('Home Assistant stable loopback/proxy configuration provisioned.')
