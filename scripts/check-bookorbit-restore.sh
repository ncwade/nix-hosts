#!/usr/bin/env bash
# Run as root on Tycho. Restores into a temporary private directory and an
# isolated PostgreSQL container; never overwrites live data.
set -euo pipefail
[ "$(id -u)" = 0 ]
umask 077
restore_dir=$(mktemp -d /var/lib/bookorbit-backup/restore-check.XXXXXX)
container=bookorbit-restore-check-$(date +%s)
cleanup() {
  podman rm -f -v "$container" >/dev/null 2>&1 || true
  rm -rf -- "$restore_dir"
}
trap cleanup EXIT
bookorbit-restic check --read-data
bookorbit-restic restore latest --host tycho --tag bookorbit --verify --target "$restore_dir"
stage=$restore_dir/var/lib/bookorbit-backup/staging
test -s "$stage/postgres.sql"
test -s "$stage/secrets/postgres"
test -d "$stage/tsidp"
# Snapshots made before the dedicated BookOrbit node have no tailnet directory.
if [ -d "$stage/tailnet" ]; then
  test -s "$stage/tailnet/tailscaled.state"
fi
if [ -f "$stage/libation/AccountsSettings.json" ]; then
  test -s "$stage/libation/LibationContext.db"
  test "$(stat -c %s "$stage/libation/libation-master.key")" = 32
fi
if [ -d "$stage/kindle" ]; then
  test -s "$stage/kindle/config.json"
  test "$(stat -c %a "$stage/kindle/config.json")" = 600
fi
mkdir -m 0711 "$restore_dir/db"
image=docker.io/pgvector/pgvector:pg18@sha256:c29f30688a9ad961691bdf0ec1650717cc132a5814619d80f80463d6e4c42e47
podman run -d --name "$container" --network none \
  -e POSTGRES_USER=restore_admin -e POSTGRES_DB=restore_control \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/postgres \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  -v "$restore_dir/db:/var/lib/postgresql/data" \
  -v "$stage/secrets:/run/secrets:ro" "$image" >/dev/null
ready=false
for attempt in $(seq 1 60); do
  if podman exec "$container" pg_isready -U restore_admin -d restore_control >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[ "$ready" = true ]
podman exec -i "$container" psql -U restore_admin -d restore_control \
  -v ON_ERROR_STOP=1 < "$stage/postgres.sql" >/dev/null
tables=$(podman exec "$container" psql -U bookorbit -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
[ "$tables" -gt 0 ]
echo "PASS: encrypted NAS1 snapshot verified and restored; SQL loaded into isolated PostgreSQL ($tables tables)."
