"""Register exact-callback OIDC clients through tsidp's existing admin grant.

Run as root on Tycho after HA owner onboarding. Never print responses or secrets.
A registration interrupted before secret storage requires explicit recovery.
"""
import json
import os
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = 'https://idp.tailf3d82.ts.net'
ROOT = Path('/var/lib/home-monitoring/secrets')


class ClientForm(HTMLParser):
    def __init__(self):
        super().__init__()
        self.fields = {}

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'input' and attrs.get('aria-label') in ('Client ID', 'Client Secret'):
            self.fields[attrs['aria-label']] = attrs['value']


def main():
    assert os.geteuid() == 0 and Path('/proc/sys/kernel/hostname').read_text().strip() == 'tycho'
    os.umask(0o077)
    for service, callback in [('grafana', '/login/generic_oauth'),
                              ('home-assistant', '/auth/oidc/callback')]:
        path = ROOT / (service + '-oidc.json')
        if path.exists():
            print(service + ': existing registration preserved')
            continue
        name = 'Tycho ' + service
        listing = urlopen(BASE + '/', timeout=20).read().decode()
        if name in listing:
            raise RuntimeError('Client exists but local secret is missing; recover before registering again')
        body = urlencode({'name': name, 'redirect_uris':
                          'https://' + service + '.tailf3d82.ts.net' + callback}).encode()
        response = urlopen(Request(BASE + '/new', data=body), timeout=20).read().decode()
        form = ClientForm()
        form.feed(response)
        assert set(form.fields) == {'Client ID', 'Client Secret'}, 'Registration failed; response suppressed'
        with path.open('x') as file:
            json.dump({'client_id': form.fields['Client ID'],
                       'client_secret': form.fields['Client Secret']}, file)
        print(service + ': registered confidential client with exact HTTPS callback')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        raise SystemExit('OIDC registration failed (' + type(error).__name__ + '); details suppressed to protect credentials') from None
