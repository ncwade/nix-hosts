#!/usr/bin/env python3
"""Smoke-test evaluated OCI definitions in disposable Docker volumes.
Usage: nix eval --json path:.#nixosConfigurations.tycho.config.virtualisation.oci-containers.containers > /tmp/containers.json
       python3 tests/bookorbit-runtime.py /tmp/containers.json
No ports are published; no production paths or secrets are used.
"""
import json, subprocess, sys, time, uuid
cfg = json.load(open(sys.argv[1]))
prefix = 'bookorbit-test-' + uuid.uuid4().hex[:8]
volumes = {p: prefix + '-' + n for p, n in [('/srv/books', 'books'), ('/var/lib/bookorbit/app', 'app'), ('/var/lib/bookorbit/postgres', 'db'), ('/var/lib/bookorbit/secrets', 'secrets')]}
containers = []
def docker(*args, check=True):
    return subprocess.run(['docker', *args], check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
def wait_for(name, command):
    for _ in range(120):
        r = docker('exec', name, *command, check=False)
        if r.returncode == 0:
            return r.stdout
        time.sleep(1)
    raise RuntimeError(docker('logs', name, check=False).stdout + docker('logs', name, check=False).stderr)
try:
    for v in volumes.values(): docker('volume', 'create', v)
    app = cfg['bookorbit']; db = cfg['bookorbit-db']
    # Use the pinned app image's shell, core utilities and /dev/urandom.
    mounts = sum((['-v', v + ':' + p] for p, v in volumes.items()), [])
    r = docker('run', '--rm', '--platform', 'linux/amd64', '--entrypoint', 'sh', *mounts, app['image'], '-ec', '''
      for name in postgres jwt bootstrap; do
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \\n' > /var/lib/bookorbit/secrets/$name
      done
      touch /srv/books/.initialized /var/lib/bookorbit/app/.initialized
      chown -R 2000:2000 /srv/books /var/lib/bookorbit/app /var/lib/bookorbit/secrets
      chmod 750 /var/lib/bookorbit/secrets
      chmod 440 /var/lib/bookorbit/secrets/*
      # Match the host mount parent; PostgreSQL owns only its PGDATA child.
      chmod 711 /var/lib/bookorbit/postgres
    ''')
    for name, spec in [('bookorbit-db', db), ('bookorbit', app)]:
        testname = prefix + '-' + name
        args = ['run', '-d', '--platform', 'linux/amd64', '--name', testname]
        if name == 'bookorbit': args += ['--network', 'container:' + prefix + '-bookorbit-db']
        for option in spec['extraOptions']:
            if option != '--network=host': args += [option]
        if spec['user']: args += ['--user', spec['user']]
        for key, value in spec['environment'].items(): args += ['-e', key + '=' + value]
        for mount in spec['volumes']:
            source, dest = mount.split(':', 1)
            if source.endswith('/secrets/postgres'):
                source = volumes['/var/lib/bookorbit/secrets']
                dest = '/run/secrets:ro'
                args += ['-e', 'POSTGRES_PASSWORD_FILE=/run/secrets/postgres']
            else: source = volumes[source]
            args += ['-v', source + ':' + dest]
        containers.append(testname)
        docker(*args, spec['image'], *spec['cmd'])
        if name == 'bookorbit-db':
            wait_for(testname, ['pg_isready', '-U', 'bookorbit', '-p', '5433'])
        else:
            wait_for(testname, ['wget', '-qO-', 'http://127.0.0.1:3000/api/v1/health'])
    dbname = prefix + '-bookorbit-db'
    extensions = docker('exec', dbname, 'psql', '-U', 'bookorbit', '-p', '5433', '-Atc', 'SELECT extname FROM pg_extension').stdout
    assert {'uuid-ossp', 'pg_trgm', 'unaccent', 'vector'} <= set(extensions.splitlines()), extensions
    dump = docker('exec', dbname, 'pg_dumpall', '-U', 'bookorbit', '-p', '5433').stdout
    assert 'PostgreSQL database cluster dump complete' in dump[-300:]
    restore_name = prefix + '-restore'
    restore_volume = prefix + '-restore-db'
    volumes['restore'] = restore_volume
    docker('volume', 'create', restore_volume)
    containers.append(restore_name)
    docker('run', '-d', '--platform', 'linux/amd64', '--name', restore_name,
           '-e', 'POSTGRES_USER=restore_admin', '-e', 'POSTGRES_DB=restore_control',
           '-e', 'POSTGRES_PASSWORD_FILE=/run/secrets/postgres',
           '-e', 'PGDATA=/var/lib/postgresql/data/pgdata',
           '-v', restore_volume + ':/var/lib/postgresql/data',
           '-v', volumes['/var/lib/bookorbit/secrets'] + ':/run/secrets:ro', db['image'],
           'postgres', '-c', 'listen_addresses=127.0.0.1', '-c', 'port=5433')
    wait_for(restore_name, ['pg_isready', '-U', 'restore_admin', '-p', '5433', '-d', 'restore_control'])
    result = subprocess.run(['docker', 'exec', '-i', restore_name, 'psql', '-U', 'restore_admin',
                             '-p', '5433', '-d', 'restore_control', '-v', 'ON_ERROR_STOP=1'],
                            input=dump, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    query = "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'"
    original = docker('exec', dbname, 'psql', '-U', 'bookorbit', '-p', '5433', '-Atc', query).stdout
    restored = docker('exec', restore_name, 'psql', '-U', 'bookorbit', '-p', '5433', '-Atc', query).stdout
    assert original == restored and int(original.strip()) > 0
    print('PASS: pinned containers, non-root read-only app, migrations, extensions, health, SQL dump and fresh-cluster restore')
finally:
    for c in reversed(containers): docker('rm', '-f', c, check=False)
    for v in volumes.values(): docker('volume', 'rm', v, check=False)
