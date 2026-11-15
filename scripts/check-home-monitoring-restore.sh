#!/usr/bin/env bash
# Read the encrypted backup into an isolated directory; never start a second HA.
set -euo pipefail
[ "$(id -u)" = 0 ]
umask 077
restore_dir=$(mktemp -d /var/lib/home-monitoring-backup/restore-check.XXXXXX)
container=home-monitoring-restore-check-$(date +%s)
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf -- "$restore_dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
bookorbit-restic restore latest --host tycho --tag home-monitoring --verify --target "$restore_dir"
stage=$restore_dir/var/lib/home-monitoring-backup/staging
state=$stage/state
test -s "$state/home-assistant/.storage/core.config_entries"
# Legacy snapshots include app-node identities. Services snapshots may omit
# them: re-enroll the shared host, retaining the control-plane Service addresses.
for app in home-assistant grafana; do
  if [ -d "$state/tailnet/$app" ]; then test -s "$state/tailnet/$app/tailscaled.state"; fi
done
python3 - "$state" <<'PY'
import sqlite3,sys
from pathlib import Path
root=Path(sys.argv[1])
for relative in ('home-assistant/home-assistant_v2.db','grafana/grafana.db'):
    with sqlite3.connect(f'file:{root / relative}?mode=ro',uri=True) as c:
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
print('Restored Home Assistant and Grafana SQLite integrity checks passed.')
PY
image=influxdb:2.9.1@sha256:e4572d094ac3272f06528ea904ce6b4cb3bb19be2db3b3b1acbd27ba5c3a73e2
docker run -d --name "$container" --network none \
  -e INFLUXD_HTTP_BIND_ADDRESS=127.0.0.1:8086 -e INFLUXD_REPORTING_DISABLED=true \
  -e INFLUXD_LOG_LEVEL=error \
  -v "$state/influxdb:/var/lib/influxdb2" \
  -v "$state/influx-config:/etc/influxdb2" \
  -v "$state/secrets:/restore-secrets:ro" "$image" >/dev/null
ready=false
for attempt in $(seq 1 60); do
  if docker exec "$container" influx ping --host http://127.0.0.1:8086 >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
[ "$ready" = true ]
docker exec "$container" sh -c '
  export INFLUX_TOKEN="$(cat /restore-secrets/grafana-read-token)"
  influx query --org home --raw '\''from(bucket: "home_history") |> range(start: -1825d) |> filter(fn: (r) => r._measurement == "home_state" and r.entity_id == "tcc_indoor_temperature" and r._field == "value") |> count()'\'' > /tmp/restore-query.csv
  grep -q tcc_indoor_temperature /tmp/restore-query.csv
'
echo 'PASS: encrypted snapshot restored and verified; restored InfluxDB queried using the restored read-only token; no second HA instance started.'
