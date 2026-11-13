set -euo pipefail
umask 077
exec 9>/run/lock/bookorbit-media.lock
flock 9
stage=/var/lib/bookorbit-backup/staging
mkdir -p "$stage" /run/bookorbit-backup
# Only the local staging tree is mutated here. Network failure cannot hold the
# application offline. ext4 has no snapshots, so pre-copy before quiescing.
mkdir -p "$stage/books" "$stage/app" "$stage/tsidp" "$stage/tailnet" "$stage/secrets" "$stage/config"
precopy() {
  local status=0
  rsync -a --delete --exclude='/.libation-in-progress/' "$1" "$2" || status=$?
  # Files may disappear during the live pre-copy. The stopped final pass is strict.
  [ "$status" -eq 0 ] || [ "$status" -eq 24 ]
}
precopy /srv/books/ "$stage/books/"
precopy /var/lib/bookorbit/app/ "$stage/app/"
trap bookorbit-backup-resume EXIT
for service in podman-bookorbit tsidp bookorbit-tailnet-serve bookorbit-tailnet; do
  if systemctl is-active --quiet "$service.service"; then
    touch "/run/bookorbit-backup/resume-$service"
    systemctl stop "$service.service"
  fi
done
# The shared lock excludes Libation while the application is stopped.
# A logical dump includes database roles and all BookOrbit extensions.
rsync -a --delete --exclude='/.libation-in-progress/' /srv/books/ "$stage/books/"
rsync -a --delete /var/lib/bookorbit/app/ "$stage/app/"
podman exec bookorbit-db pg_dumpall -U bookorbit -p 5433 > "$stage/postgres.sql.tmp"
test -s "$stage/postgres.sql.tmp"
tail -n 5 "$stage/postgres.sql.tmp" | grep -q 'PostgreSQL database cluster dump complete'
mv "$stage/postgres.sql.tmp" "$stage/postgres.sql"
tsidp_state=$(readlink -f /var/lib/tsidp)
test -d "$tsidp_state"
rsync -a --delete "$tsidp_state/" "$stage/tsidp/"
rsync -a --delete /var/lib/bookorbit-tailnet/ "$stage/tailnet/"
rsync -a --delete /var/lib/bookorbit/secrets/ "$stage/secrets/"
rsync -a --delete /etc/bookorbit/ "$stage/config/"
if [ -d /var/lib/libation ]; then
  mkdir -p "$stage/libation"
  rsync -a --delete /var/lib/libation/ "$stage/libation/"
fi
if [ -d /var/lib/bookorbit-kindle ]; then
  mkdir -p "$stage/kindle"
  # The shared media lock also excludes acquisition and private key writes.
  rsync -a --delete --exclude='/work/' /var/lib/bookorbit-kindle/ "$stage/kindle/"
fi
if [ -d /var/lib/bookorbit-alerts ]; then
  exec 7>/var/lib/bookorbit-alerts/check.lock
  flock 7
  mkdir -p "$stage/alerts" "$stage/connector-health"
  rsync -a --delete /var/lib/bookorbit-alerts/ "$stage/alerts/"
  rsync -a --delete /var/lib/bookorbit-connector-health/ "$stage/connector-health/"
  flock -u 7
fi
bookorbit-backup-resume
trap - EXIT
flock -u 9
# The repository is initialized explicitly during provisioning: failures here
# must never be mistaken for an empty repository or reset encryption keys.
bookorbit-restic backup --host tycho --tag bookorbit "$stage"
bookorbit-restic check
bookorbit-restic forget --host tycho --tag bookorbit --group-by host,tags \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
date -u +%FT%TZ > /var/lib/bookorbit-backup/last-success
