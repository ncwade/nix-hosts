#!/usr/bin/env python3
"""Read only HA's entity registry and recorder. No credentials or control calls."""
import json
from pathlib import Path
import sqlite3

root = Path('/var/lib/home-monitoring/home-assistant')
registry = root / '.storage/core.entity_registry'
if not registry.exists():
    raise SystemExit('Home Assistant onboarding has not finished.')
entities = [e for e in json.loads(registry.read_text())['data']['entities'] if e.get('platform') == 'honeywell']
print('Honeywell entity count:',len(entities))
db = sqlite3.connect(f'file:{root / "home-assistant_v2.db"}?mode=ro', uri=True)
attrs = {'friendly_name','current_temperature','current_humidity','temperature','target_temp_low','target_temp_high','hvac_action','hvac_modes','fan_mode','fan_modes','fan_action','supported_features','unit_of_measurement','device_class'}
for entity in entities:
    eid = entity['entity_id']
    print(json.dumps({'entity_id': eid, 'disabled_by':entity.get('disabled_by')}))
    row = db.execute('''SELECT s.state, s.last_updated_ts, a.shared_attrs FROM states s
        JOIN states_meta m ON s.metadata_id=m.metadata_id
        LEFT JOIN state_attributes a ON s.attributes_id=a.attributes_id
        WHERE m.entity_id=? ORDER BY s.state_id DESC LIMIT 1''', (eid,)).fetchone()
    if row:
        attributes = json.loads(row[2] or '{}')
        print(json.dumps({'state':row[0], 'last_changed_record_ts':row[1], 'attributes':{k:v for k,v in attributes.items() if k in attrs}}))
    else: print('No recorded state yet (may be disabled).')
