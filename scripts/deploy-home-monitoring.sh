#!/usr/bin/env bash
# Run on Tycho from an isolated copy of its CURRENT configuration plus this change.
set -euo pipefail
[ "$(hostname)" = tycho ] && [ "$(id -u)" = 0 ] || exit 2
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec 8>/run/lock/home-monitoring-deploy.lock
flock -n 8
previous=$(readlink -f /run/current-system)
backup=/var/lib/nixos-source-backups/monitoring-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 0700 "$backup"
cp -a /etc/nixos "$backup/nixos"
printf '%s\n' "$previous" > "$backup/system"
nixos-rebuild build --flake "path:$source_dir#tycho" --no-write-lock-file
# An unrelated import can continue only if its active unit is identical.
for unit in bookorbit-kindle-sync bookorbit-kindle bookorbit-audible bookorbit-backup; do
  case "$(systemctl show "$unit" -p ActiveState --value)" in
    active|activating)
      cmp "/run/current-system/etc/systemd/system/$unit.service" \
        "result/etc/systemd/system/$unit.service" || {
          echo "Active $unit would change; retry after it finishes." >&2; exit 1;
        } ;;
  esac
done
trap '"$previous/bin/switch-to-configuration" test' ERR
nixos-rebuild test --flake "path:$source_dir#tycho" --no-write-lock-file
for port in 8123 3002 8086; do
  case "$port" in 8123) route=/ ;; 3002) route=/api/health ;; 8086) route=/health ;; esac
  ready=false
  for attempt in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:$port$route" >/dev/null 2>&1; then ready=true; break; fi
    sleep 2
  done
  [ "$ready" = true ]
done
systemctl is-active podman-bookorbit podman-bookorbit-db tsidp rex-login-server ntfy-sh
nixos-rebuild switch --flake "path:$source_dir#tycho" --no-write-lock-file
trap - ERR
# Copy only this feature; preserve all independently deployed host changes.
cp -a "$source_dir/modules/nixos/home-monitoring" /etc/nixos/modules/nixos/
cp -a "$source_dir/hosts/tycho/monitoring.nix" /etc/nixos/hosts/tycho/
if ! grep -q './monitoring.nix' /etc/nixos/hosts/tycho/default.nix; then
  sed -i '/\.\/rex.nix/a\    ./monitoring.nix' /etc/nixos/hosts/tycho/default.nix
fi
cp -a "$source_dir/scripts/deploy-home-monitoring.sh" /etc/nixos/scripts/
cp -a "$source_dir/scripts/backup-home-monitoring.sh" /etc/nixos/scripts/
cp -a "$source_dir/scripts/check-home-monitoring.py" /etc/nixos/scripts/
cp -a "$source_dir/scripts/inspect-tcc.py" /etc/nixos/scripts/
cp -a "$source_dir/scripts/check-home-monitoring-restore.sh" /etc/nixos/scripts/
cp -a "$source_dir/scripts/register-monitoring-oidc.py" /etc/nixos/scripts/
cp -a "$source_dir/docs/home-monitoring.md" /etc/nixos/docs/
install -d /etc/nixos/tests
cp -a "$source_dir/tests/home-monitoring.py" "$source_dir/tests/home-monitoring-sso.py" "$source_dir/tests/home-monitoring-runtime.py" /etc/nixos/tests/
echo "Monitoring activated. Previous configuration: $backup"
