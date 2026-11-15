#!/usr/bin/env bash
# Run as root on Tycho from a staged copy of its current /etc/nixos.
set -euo pipefail
[ "$(hostname)" = tycho ] && [ "$(id -u)" = 0 ] || exit 2
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_dir"
phase=$(nix eval --raw "path:$source_dir#nixosConfigurations.tycho.config.personal.tailnetServices.phase")
case "$phase" in prepare|services|legacy) ;; *) exit 2 ;; esac

# Exclude backups and prevent new imports during the short cutover. Existing
# imports may continue only in the Services phase, with identical unit files
# verified below. This changes routing, not application processes or storage.
exec 8>/run/lock/home-monitoring-deploy.lock
flock -n 8 || { echo 'Monitoring deployment or backup is active; retry later.' >&2; exit 1; }
resume_timers=()
resume() {
  if [ "${#resume_timers[@]}" -gt 0 ]; then systemctl start "${resume_timers[@]}"; fi
}
trap resume EXIT
for unit in bookorbit-backup bookorbit-audible bookorbit-kindle bookorbit-kindle-sync; do
  if systemctl is-active --quiet "$unit.timer"; then
    resume_timers+=("$unit.timer")
    systemctl stop "$unit.timer"
  fi
done
case "$(systemctl show bookorbit-backup -p ActiveState --value)" in
  active|activating|deactivating) echo 'BookOrbit backup is active; retry later.' >&2; exit 1 ;;
esac
exec 9>/run/lock/bookorbit-media.lock
if ! flock -n 9; then
  running_import=false
  for unit in bookorbit-audible bookorbit-kindle bookorbit-kindle-sync; do
    case "$(systemctl show "$unit" -p ActiveState --value)" in
      active|activating) running_import=true ;;
    esac
  done
  [ "$phase" = services ] && [ "$running_import" = true ] || {
    echo 'Media lock is busy; retry after the current operation finishes.' >&2; exit 1;
  }
fi

if [ "$phase" = services ]; then
  tailscale --socket=/run/tailnet-services/tailscaled.sock status --json |
    python3 -c 'import json,sys; s=json.load(sys.stdin); sys.exit(0 if s.get("BackendState") == "Running" and "tag:tycho-services" in (s.get("Self", {}).get("Tags") or []) else 1)'
fi
previous=$(readlink -f /run/current-system)
backup=/var/lib/nixos-source-backups/tailnet-services-$(date -u +%Y%m%dT%H%M%SZ)
install -d -m 0700 "$backup"
cp -a /etc/nixos "$backup/nixos"
printf '%s\n' "$previous" > "$backup/system"
nixos-rebuild build --flake "path:$source_dir#tycho" --no-write-lock-file

# Refuse stale source or unintended application changes before activation.
for unit in tailscaled rex-login-server rex-tailscale-serve tsidp home-monitoring \
  podman-bookorbit podman-bookorbit-db nginx bookorbit-serve; do
  cmp "$previous/etc/systemd/system/$unit.service" "result/etc/systemd/system/$unit.service" || {
    echo "$unit would change. Reconcile the staged source with the live host first." >&2
    exit 1
  }
done
for unit in bookorbit-audible bookorbit-kindle bookorbit-kindle-sync bookorbit-backup; do
  case "$(systemctl show "$unit" -p ActiveState --value)" in
    active|activating)
      cmp "$previous/etc/systemd/system/$unit.service" "result/etc/systemd/system/$unit.service" || {
        echo "Active $unit would change; retry after it finishes." >&2
        exit 1
      } ;;
  esac
done
rollback() {
  echo "Activation failed; restoring runtime $previous. Source backup: $backup" >&2
  "$previous/bin/switch-to-configuration" test || true
  if [ "$phase" = services ]; then
    echo 'Also restore application DNS names in Tailscale; see docs/tailscale-services.md.' >&2
  fi
}
trap rollback ERR
nixos-rebuild test --flake "path:$source_dir#tycho" --no-write-lock-file
systemctl is-active tailscaled rex-login-server tsidp home-monitoring podman-bookorbit podman-bookorbit-db nginx

if [ "$phase" = services ]; then
  systemctl is-active tailnet-services tailnet-services-publish
  for app in bookorbit home-assistant grafana; do
    if systemctl is-active --quiet "$app-tailnet"; then
      echo "Legacy $app node is still active; refusing cutover." >&2
      false
    fi
  done
  # With legacy nodes stopped, successful HTTPS proves the Service route works.
  for endpoint in bookorbit:/api/v1/health home-assistant:/ grafana:/api/health; do
    name=${endpoint%%:*}
    route=${endpoint#*:}
    ready=false
    for attempt in $(seq 1 30); do
      if curl -fsS --connect-timeout 3 --max-time 5 "https://$name.tailf3d82.ts.net$route" >/dev/null; then
        ready=true
        break
      fi
      sleep 2
    done
    [ "$ready" = true ]
    headers=$(curl -sS --connect-timeout 3 --max-time 5 -D - -o /dev/null "http://$name.tailf3d82.ts.net/migration-check?keep=query")
    printf '%s\n' "$headers" | tr -d '\r' | grep -Fiqx "Location: https://$name.tailf3d82.ts.net/migration-check?keep=query"
  done
  curl -fsS --connect-timeout 3 --max-time 10 https://idp.tailf3d82.ts.net/.well-known/openid-configuration >/dev/null
elif [ "$phase" = prepare ]; then
  systemctl is-active tailnet-services tailnet-services-prepare
  for app in bookorbit home-assistant grafana; do systemctl is-active "$app-tailnet" "$app-tailnet-serve"; done
fi

nixos-rebuild switch --flake "path:$source_dir#tycho" --no-write-lock-file
trap - ERR
# Copy only migration files; the staged tree must already include live changes.
for path in hosts/tycho/tailnet-services.nix hosts/tycho/default.nix \
  modules/nixos/bookorbit/default.nix modules/nixos/bookorbit/backup.sh \
  modules/nixos/home-monitoring/tailnet.nix scripts/backup-home-monitoring.sh \
  scripts/check-home-monitoring-restore.sh scripts/deploy-bookorbit.sh \
  scripts/deploy-home-monitoring.sh scripts/deploy-tailnet-services.sh \
  tests/tailnet-services.nix tests/tailnet-services-publish.py tests/home-monitoring-backup.py \
  tests/bookorbit-backup.py docs/tailscale-services.md docs/bookorbit.md \
  docs/home-monitoring.md README.md; do
  install -D -m 0644 "$source_dir/$path" "/etc/nixos/$path"
done
cp -a "$source_dir/modules/nixos/tailnet-services" /etc/nixos/modules/nixos/
printf 'Activated phase %s. Previous configuration: %s\n' "$phase" "$backup"
