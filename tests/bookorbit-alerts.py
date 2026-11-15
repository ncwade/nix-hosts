#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import os
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1] / 'modules/nixos/bookorbit'

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

alerts = load('alerts')
health = load('audible-health')

class AlertsTest(unittest.TestCase):
    def test_health_exports_latched_incidents_and_requires_acceptance(self):
        with tempfile.TemporaryDirectory() as temp:
            token = Path(temp) / 'token'
            token.write_text('private-test-token')
            state = {}
            alerts.transition(state, 'kindle', 'failed', 0, 10)
            alerts.transition(state, 'kindle', None, 5, 20)
            with patch.object(alerts.urllib.request, 'urlopen') as send:
                send.return_value.__enter__.return_value.status = 204
                alerts.publish_health(state, token)
                request = send.call_args.args[0]
                self.assertIn(b'connector=kindle failed=1i ', request.data)
                self.assertIn(b'connector=audible failed=0i ', request.data)
                self.assertEqual(request.get_header('Authorization'), 'Token private-test-token')
                send.return_value.__enter__.return_value.status = 200
                with self.assertRaises(RuntimeError): alerts.publish_health(state, token)

    def test_recovery_during_export_outage_does_not_hide_the_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            token = Path(temp) / 'token'
            token.write_text('private-test-token')
            state = {}
            alerts.transition(state, 'kindle', 'failed', 0, 10)
            alerts.transition(state, 'kindle', None, 15, 20)
            self.assertNotIn('kindle', state['incidents'])
            with patch.dict(os.environ, BOOKORBIT_INFLUX_TOKEN_FILE=str(token)), \
                    patch.object(alerts.urllib.request, 'urlopen') as send:
                send.return_value.__enter__.return_value.status = 204
                alerts.deliver(state, Path(temp) / 'state.json')
                self.assertIn(b'connector=kindle failed=1i ', send.call_args.args[0].data)
                alerts.deliver(state, Path(temp) / 'state.json')
                self.assertIn(b'connector=kindle failed=0i ', send.call_args.args[0].data)

    def test_cutover_preserves_incidents_and_retries_failed_exports(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            state = {'incidents': {'kindle': {'since': 10}}, 'pending': [{'kind': 'failure'}]}
            alerts.save(path, state)
            with patch.dict(os.environ, BOOKORBIT_INFLUX_TOKEN_FILE='unused'), \
                    patch.object(alerts, 'publish_health') as health:
                health.side_effect = OSError('offline')
                with self.assertRaises(OSError): alerts.deliver(state, path)
                self.assertTrue(json.loads(path.read_text())['pending'])
                health.side_effect = None
                alerts.deliver(state, path)
                self.assertFalse(json.loads(path.read_text())['pending'])
                self.assertIn('kindle', json.loads(path.read_text())['incidents'])

    def test_missing_exporter_credential_fails_without_discarding_state(self):
        state = {'incidents': {'kindle': {'since': 10}}, 'pending': [{'kind': 'failure'}]}
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError): alerts.deliver(state, Path('/unused'))
        self.assertTrue(state['pending'])

    def test_incident_dedup_lock_deferral_and_recovery(self):
        state = {}
        alerts.transition(state, 'kindle', 'failed', 0, 10)
        alerts.transition(state, 'kindle', 'failed', 0, 20)
        alerts.transition(state, 'kindle', None, 5, 30)  # Lock deferral, old marker.
        self.assertEqual(len(state['pending']), 1)
        alerts.transition(state, 'kindle', None, 35, 40)
        alerts.transition(state, 'kindle', None, 35, 50)
        self.assertEqual([e['kind'] for e in state['pending']], ['failure', 'recovery'])
        alerts.transition(state, 'kindle', 'failed again', 35, 60)
        self.assertEqual(len(state['pending']), 3)

    def test_running_service_cannot_clear_incident(self):
        with patch.object(alerts.subprocess, 'run') as run:
            run.return_value.stdout = 'LoadState=loaded\nActiveState=activating\nResult=success\n'
            self.assertEqual(alerts.inspect('kindle', Path('/unused')), (None, 0))

    def test_missing_credentials_fail(self):
        with patch.object(alerts.subprocess, 'run') as run:
            run.return_value.stdout = 'LoadState=loaded\nActiveState=inactive\nResult=success\nConditionResult=no\n'
            self.assertIsNotNone(alerts.inspect('audible', Path('/unused'))[0])

    def test_partial_download_detection(self):
        book = dict(IsAudiblePlus=False, AbsentFromLastScan=False, ContentType='Product',
                    BookStatus='Liberated', HasPdf=True, PdfStatus='Liberated')
        health.check([book], 'Done. All books have been processed')
        for field in ['BookStatus', 'PdfStatus']:
            with self.assertRaises(ValueError): health.check([{**book, field: 'NotLiberated'}], 'Done.')
        limit = "Done. Stopped early: this run's download limit was reached."
        health.check([{**book, 'BookStatus': 'NotLiberated'}], limit)
        with self.assertRaises(ValueError):
            health.check([{**book, 'BookStatus': 'NotLiberated'}], 'Error processing book.\n' + limit)
        health.check([{**book, 'IsAudiblePlus': True, 'BookStatus': 'NotLiberated'}], 'Done.')
        health.check([{**book, 'AbsentFromLastScan': True, 'BookStatus': 'NotLiberated'}], 'Done.')

if __name__ == '__main__': unittest.main()
