"""Install pinned OIDC code and private configuration while Home Assistant is stopped."""
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile

os.umask(0o077)
root = Path('/var/lib/home-monitoring')
ha = root / 'home-assistant'
env = root / 'secrets/grafana.env'
# Fresh installs retain local onboarding until both clients have been registered.
if (root / 'secrets/sso-disabled').exists() or not all(
        (root / 'secrets' / (name + '-oidc.json')).exists()
        for name in ('home-assistant', 'grafana')):
    with env.open('a') as f:
        f.write('GF_AUTH_GENERIC_OAUTH_ENABLED=false\n')
    print('SSO disabled or not enrolled; local sign-in retained.')
    sys.exit(0)
clients = {name: json.loads((root / 'secrets' / (name + '-oidc.json')).read_text())
           for name in ('home-assistant', 'grafana')}
auth = json.loads((ha / '.storage/auth').read_text())['data']
owner = next(user for user in auth['users'] if user.get('is_owner'))
credentials = [c for c in auth['credentials'] if c['user_id'] == owner['id']]
assert any(c['auth_provider_type'] == 'homeassistant' and c['data'].get('username') == 'ncwade'
           for c in credentials), 'Expected local owner must exist before enabling SSO'
linked = any(c['auth_provider_type'] == 'auth_oidc' for c in credentials)

component = ha / 'custom_components/auth_oidc'
staging = component.with_name('auth_oidc-install')
if staging.exists():
    shutil.rmtree(staging)
staging.mkdir(parents=True)
with zipfile.ZipFile(sys.argv[1]) as archive:
    archive.extractall(staging)
assert json.loads((staging / 'manifest.json').read_text())['version'] == '1.2.1'
if component.exists():
    shutil.rmtree(component)
staging.rename(component)

configuration = {
    **clients['home-assistant'],
    'discovery_url': 'https://idp.tailf3d82.ts.net/.well-known/openid-configuration',
    'display_name': 'Tailscale',
    'claims': {'username': 'username', 'display_name': 'name', 'groups': 'groups'},
    'roles': {'user': 'home-monitoring-admin', 'admin': 'home-monitoring-admin'},
    'features': {
        'automatic_user_linking': not linked,
        'automatic_person_creation': False,
        'include_groups_scope': False,
        'default_redirect': False,
    },
    'additional_scopes': ['email'],
}
(ha / 'oidc.yaml').write_text(json.dumps(configuration, indent=2) + '\n')
with (ha / 'configuration.yaml').open('a') as f:
    f.write('\nauth_oidc: !include oidc.yaml\n')
lines = [line for line in env.read_text().splitlines()
         if not line.startswith(('GF_AUTH_GENERIC_OAUTH_ENABLED=', 'GF_AUTH_GENERIC_OAUTH_CLIENT_ID=', 'GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET='))]
lines.append('GF_AUTH_GENERIC_OAUTH_ENABLED=true')
for key, value in clients['grafana'].items():
    assert '\n' not in value and '$' not in value
    lines.append('GF_AUTH_GENERIC_OAUTH_' + key.upper() + '=' + value)
env.write_text('\n'.join(lines) + '\n')
print('SSO configured with required group; local passwords retained; owner linking ' + ('disabled' if linked else 'pending first login'))
