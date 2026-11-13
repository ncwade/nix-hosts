#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
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

    def test_transport_failure_retains_events_for_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'state.json'
            state = {'pending': [{'kind': 'failure'}, {'kind': 'recovery'}]}
            alerts.save(path, state)
            def fail(event): raise OSError('offline')
            with self.assertRaises(OSError): alerts.flush(state, path, fail)
            self.assertEqual(len(json.loads(path.read_text())['pending']), 2)
            sent = []
            alerts.flush(state, path, sent.append)
            self.assertEqual([e['kind'] for e in sent], ['failure', 'recovery'])
            self.assertFalse(json.loads(path.read_text())['pending'])

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
