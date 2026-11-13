#!/usr/bin/env bash
# Run on the target host from a reviewed source checkout. Never installs disks.
set -euo pipefail
host=${1:?Usage: sudo bash scripts/deploy-bookorbit.sh tycho-or-nas1}
case "$host" in tycho|nas1) ;; *) exit 2 ;; esac
[ "$(id -u)" = 0 ] || { echo 'Run this script through sudo on the target host.' >&2; exit 1; }
[ "$(hostname)" = "$host" ] || { echo 'Host mismatch; refusing activation.' >&2; exit 1; }
if [ "$host" = tycho ]; then
  # Activation must not overlap the backup's application shutdown or downloads.
  exec 8>/run/lock/bookorbit-media.lock
  flock 8
fi
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
previous_system=$(readlink -f /run/current-system)
backup_dir=/var/lib/nixos-source-backups/bookorbit-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p -m 0700 "$backup_dir"
cp -a /etc/nixos "$backup_dir/nixos"
printf '%s\n' "$previous_system" > "$backup_dir/system"
nixos-rebuild build --flake "path:$source_dir#$host" --no-write-lock-file
rollback() {
  echo "Activation failed; restoring previous runtime configuration: $previous_system" >&2
  "$previous_system/bin/switch-to-configuration" test
}
trap rollback ERR
nixos-rebuild test --flake "path:$source_dir#$host" --no-write-lock-file
if [ "$host" = tycho ]; then
  healthy=false
  for attempt in $(seq 1 120); do
    if curl --fail --silent http://127.0.0.1:3000/api/v1/health >/dev/null; then
      healthy=true
      break
    fi
    sleep 2
  done
  [ "$healthy" = true ]
  systemctl is-active tsidp bookorbit-serve bookorbit-tailnet bookorbit-tailnet-serve nginx
else
  systemctl is-active nas1-documents nas1-bookorbit-backup-directory
  test -d /mnt/Data/documents/backups/tycho/bookorbit
  sshd -t
fi
nixos-rebuild switch --flake "path:$source_dir#$host" --no-write-lock-file
trap - ERR
# Source of truth for subsequent rebuilds; retain the previous tree above.
for entry in flake.nix flake.lock modules hosts programs installer scripts tests docs README.md; do
  cp -a "$source_dir/$entry" /etc/nixos/
done
printf 'Activated %s. Previous source and system reference: %s\n' "$host" "$backup_dir"
printf 'Continue credential provisioning and OIDC setup in docs/bookorbit.md.\n'
