#!/usr/bin/env bash
# Consistent cold snapshot; encrypted with Tycho's existing NAS1 restic setup.
set -euo pipefail
[ "$(cat /proc/sys/kernel/hostname)" = tycho ] && [ "$(id -u)" = 0 ] || exit 2
exec 9>/run/lock/home-monitoring-deploy.lock
flock -n 9
stage=/var/lib/home-monitoring-backup/staging
install -d -m 0700 "$stage"
# Large initial copy while running, then short stopped reconciliation.
rsync -a --delete /var/lib/home-monitoring/ "$stage/state/"
units=(home-monitoring home-assistant-tailnet grafana-tailnet home-assistant-tailnet-serve grafana-tailnet-serve)
resume_units=()
for unit in "${units[@]}"; do
  if systemctl is-active --quiet "$unit"; then resume_units+=("$unit"); fi
done
resume() { if [ "${#resume_units[@]}" -gt 0 ]; then systemctl start "${resume_units[@]}"; fi; }
trap resume EXIT
trap 'exit 130' INT TERM
systemctl stop "${units[@]}"
rsync -a --delete /var/lib/home-monitoring/ "$stage/state/"
rsync -a --delete /etc/nixos/modules/nixos/home-monitoring/ "$stage/configuration/"
docker images --digests --format '{{.Repository}}:{{.Tag}} {{.Digest}}' > "$stage/images.txt"
resume
trap - EXIT
/run/current-system/sw/bin/bookorbit-restic backup --host tycho --tag home-monitoring "$stage"
/run/current-system/sw/bin/bookorbit-restic check
/run/current-system/sw/bin/bookorbit-restic forget --tag home-monitoring --group-by host,paths,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6
printf 'Encrypted monitoring backup complete. Verify with bookorbit-restic snapshots --tag home-monitoring.\n'
