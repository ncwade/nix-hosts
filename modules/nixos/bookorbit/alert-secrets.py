"""Create credentials once; keep plaintext and hashes out of the Nix store."""
import json
import os
from pathlib import Path
import secrets
import bcrypt

os.umask(0o077)
root = Path('/var/lib/bookorbit-alerts')
credentials = root / 'credentials.json'
if not credentials.exists():
    data = {name: secrets.token_urlsafe(24) for name in ('bookorbit-publisher', 'ncwade')}
    temporary = credentials.with_suffix('.tmp')
    temporary.write_text(json.dumps(data) + '\n')
    temporary.replace(credentials)
data = json.loads(credentials.read_text())
env = root / 'ntfy.env'
if not env.exists():
    users = ','.join(f'{name}:{bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()}:user'
                     for name, password in data.items())
    temporary = env.with_suffix('.tmp')
    temporary.write_text(f"NTFY_AUTH_USERS='{users}'\n")
    temporary.replace(env)
