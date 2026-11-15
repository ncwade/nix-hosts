"""Provision the Grafana → HA → selected iPhone route without exposing secrets."""
import json
import os
from pathlib import Path
import re
import secrets


def rule(connector, label, enabled):
    # Keep short failures visible for at least one evaluation. Recovery follows
    # five minutes of healthy samples; absent telemetry becomes an alert too.
    query = ('from(bucket: "home_history") |> range(start: -5m) '
             '|> filter(fn: (r) => r._measurement == "bookorbit_health" '
             f'and r.host == "tycho" and r.connector == "{connector}" and r._field == "failed") '
             '|> max() |> keep(columns: ["_time", "_value"])')
    return {
        'uid': 'bookorbit-' + connector,
        'title': 'BookOrbit: ' + label,
        'condition': 'C', 'for': '0s',
        'noDataState': 'Alerting', 'execErrState': 'Alerting',
        'isPaused': not enabled,
        'labels': {'service': 'bookorbit', 'connector': connector, 'host': 'tycho'},
        'annotations': {'summary': label + ' needs attention, or its health feed is unavailable. '
                       'Check the connector status on Tycho.'},
        'notification_settings': {
            'receiver': 'home-assistant-iphone',
            'group_by': ['grafana_folder', 'alertname'],
            'group_wait': '0s', 'group_interval': '1m', 'repeat_interval': '4h',
        },
        'data': [
            {'refId': 'A', 'datasourceUid': 'home-history',
             'relativeTimeRange': {'from': 300, 'to': 0},
             'model': {'refId': 'A', 'query': query, 'intervalMs': 60000, 'maxDataPoints': 300,
                       'datasource': {'type': 'influxdb', 'uid': 'home-history'}}},
            {'refId': 'B', 'datasourceUid': '__expr__',
             'relativeTimeRange': {'from': 0, 'to': 0},
             'model': {'refId': 'B', 'type': 'reduce', 'expression': 'A', 'reducer': 'last',
                       'datasource': {'type': '__expr__', 'uid': '__expr__'}}},
            {'refId': 'C', 'datasourceUid': '__expr__',
             'relativeTimeRange': {'from': 0, 'to': 0},
             'model': {'refId': 'C', 'type': 'threshold', 'expression': 'B',
                       'conditions': [{'evaluator': {'type': 'gt', 'params': [0]},
                                       'operator': {'type': 'and'}, 'query': {'params': ['C']},
                                       'reducer': {'type': 'last', 'params': []}, 'type': 'query'}],
                       'datasource': {'type': '__expr__', 'uid': '__expr__'}}},
        ],
    }


def configure(root):
    private = root / 'secrets'
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    webhook_file = private / 'grafana-webhook-id'
    if not webhook_file.exists():
        webhook_file.write_text(secrets.token_hex(32) + '\n')
        webhook_file.chmod(0o600)
    webhook = webhook_file.read_text().strip()
    if not re.fullmatch(r'[0-9a-f]{64}', webhook):
        raise ValueError('Invalid Grafana webhook ID; refusing to replace it')
    target_file = private / 'iphone-notify-service'
    target = target_file.read_text().strip() if target_file.exists() else ''
    if target and not re.fullmatch(r'notify\.mobile_app_[a-z0-9_]+', target):
        raise ValueError('Expected an exact notify.mobile_app service name')
    enabled = bool(target)
    # Do not guess a device or broadcast to every registered phone. With no
    # selected target, provision paused rules and no notification automation.
    package = {'automation': []}
    if enabled:
        package['automation'].append({
            'id': 'grafana_iphone_alerts', 'alias': 'Grafana alerts to iPhone',
            'description': 'Notification delivery only; never operates home devices.',
            'mode': 'queued', 'max': 50,
            'triggers': [{'trigger': 'webhook', 'webhook_id': webhook,
                          'allowed_methods': ['POST'], 'local_only': True}],
            'actions': [{'repeat': {
                'for_each': '{{ trigger.json.alerts | default([]) }}',
                'sequence': [{'action': target, 'data': {
                    'title': "{{ 'Recovered' if repeat.item.status == 'resolved' else 'Alert' }}: "
                             "{{ repeat.item.labels.alertname | default('Grafana') }}",
                    'message': "{% if repeat.item.status == 'resolved' %}The alert has cleared. "
                               "{% else %}{{ repeat.item.annotations.summary | default('Open Grafana for details.', true) }}{% endif %}",
                    'data': {'url': 'https://grafana.tailf3d82.ts.net/alerting/list',
                             'group': 'grafana-tycho',
                             'tag': "grafana-{{ repeat.item.fingerprint | default(repeat.item.labels.alertname) }}"},
                }}],
            }}],
        })
    packages = root / 'home-assistant/packages'
    packages.mkdir(parents=True, exist_ok=True)
    package_file = packages / 'grafana_alerts.yaml'
    package_file.write_text(json.dumps(package, indent=2) + '\n')
    package_file.chmod(0o600)

    config = {
        'apiVersion': 1,
        'contactPoints': [{'orgId': 1, 'name': 'home-assistant-iphone', 'receivers': [{
            'uid': 'home-assistant-iphone', 'type': 'webhook', 'disableResolveMessage': False,
            'settings': {'url': 'http://127.0.0.1:8123/api/webhook/' + webhook,
                         'httpMethod': 'POST', 'maxAlerts': '0'},
        }]}],
        'groups': [{'orgId': 1, 'name': 'BookOrbit connectors', 'folder': 'Tycho alerts',
                    'interval': '1m', 'rules': [rule(name, label, enabled) for name, label in (
                        ('audible', 'Audible downloads'), ('kindle', 'Kindle import'),
                        ('kindle-sync', 'Kindle downloads'))]}],
    }
    directory = root / 'alerting'
    directory.mkdir(exist_ok=True)
    directory.chmod(0o750)
    os.chown(directory, 0, 472)
    output = directory / 'bookorbit.json'
    output.write_text(json.dumps(config, indent=2) + '\n')
    os.chown(output, 0, 472)
    output.chmod(0o640)
    print('Grafana iPhone alerting configured.' if enabled else
          'Grafana rules paused: select the registered iPhone notify service before enabling delivery.')


if __name__ == '__main__':
    os.umask(0o077)
    configure(Path('/var/lib/home-monitoring'))
