"""Install managed HA export options; connection settings live in the UI.

On a brand new installation only, seed the supported automatic YAML import.
Subsequent starts remove those legacy keys once the config entry exists.
No config entries or credentials are ever printed or rewritten here.
"""
import json
import os
from pathlib import Path
import sys

os.umask(0o077)
root = Path('/var/lib/home-monitoring/home-assistant')
entries = root / '.storage/core.config_entries'
imported = False
if entries.exists():
    imported = any(e['domain'] == 'influxdb' for e in json.loads(entries.read_text())['data']['entries'])
configuration = Path(sys.argv[1]).read_text()
if not imported:
    connection = '''influxdb:
  api_version: 2
  host: 127.0.0.1
  port: 8086
  ssl: false
  token: !secret influx_write_token
  organization: home
  bucket: home_history
'''
    configuration = configuration.replace('influxdb:\n', connection, 1)
    print('Preparing one-time InfluxDB connection import; restart after successful import to remove legacy keys.')
else:
    print('InfluxDB UI connection preserved; YAML contains supported export options only.')
(root / 'configuration.yaml').write_text(configuration)
