#!/usr/bin/env python3
"""Provisioning is repeatable, private, and inactive until a phone is selected."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'modules/nixos/home-monitoring/configure_alerting.py'
spec = importlib.util.spec_from_file_location('alerting', SOURCE)
alerting = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alerting)


class AlertingTest(unittest.TestCase):
    def test_safe_onboarding_and_repeatable_activation(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(alerting.os, 'chown'):
            root = Path(temp)
            alerting.configure(root)
            webhook = (root / 'secrets/grafana-webhook-id').read_text()
            rules = json.loads((root / 'alerting/bookorbit.json').read_text())['groups'][0]['rules']
            self.assertTrue(all(rule['isPaused'] for rule in rules))
            self.assertEqual(json.loads((root / 'home-assistant/packages/grafana_alerts.yaml').read_text())['automation'], [])
            (root / 'secrets/iphone-notify-service').write_text('notify.mobile_app_test_iphone\n')
            alerting.configure(root)
            before = (root / 'alerting/bookorbit.json').read_text()
            alerting.configure(root)
            self.assertEqual(before, (root / 'alerting/bookorbit.json').read_text())
            self.assertEqual(webhook, (root / 'secrets/grafana-webhook-id').read_text())
            self.assertTrue(all(not r['isPaused'] for r in json.loads(before)['groups'][0]['rules']))
            automation = json.loads((root / 'home-assistant/packages/grafana_alerts.yaml').read_text())['automation'][0]
            self.assertEqual(automation['actions'][0]['repeat']['sequence'][0]['action'], 'notify.mobile_app_test_iphone')
            self.assertTrue(automation['triggers'][0]['local_only'])
            self.assertEqual((root / 'alerting/bookorbit.json').stat().st_mode & 0o777, 0o640)
            self.assertEqual((root / 'secrets/grafana-webhook-id').stat().st_mode & 0o777, 0o600)

    def test_invalid_target_cannot_invoke_another_service(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(alerting.os, 'chown'):
            root = Path(temp)
            alerting.configure(root)
            (root / 'secrets/iphone-notify-service').write_text('lock.unlock')
            with self.assertRaises(ValueError): alerting.configure(root)


if __name__ == '__main__':
    unittest.main()
