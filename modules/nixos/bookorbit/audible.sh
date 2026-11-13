set -euo pipefail
# Both the downloader and backup hold this lock for their local writes.
exec 9>/run/lock/bookorbit-media.lock
flock 9
install -o bookorbit -g bookorbit -m 0600 \
  /etc/bookorbit/libation-settings.json /var/lib/libation/Settings.json
# Leave room for a second copy of the library in backup staging.
available=$(df --output=avail -B1 /srv/books | tail -1)
library=$(du -sb /srv/books/audiobooks | cut -f1)
if (( available < library + 50 * 1024 * 1024 * 1024 )); then
  echo "Insufficient space for Audible downloads and backup staging" >&2
  exit 1
fi
bookorbit-audible-cli scan
bookorbit-audible-cli set-status --downloaded --download-pending
bookorbit-audible-cli liberate --limit-gb 20 2>&1 | tee /var/lib/libation/last-download.log
bookorbit-audible-cli export --json --path /config/inventory.json
python3 "$AUDIBLE_HEALTH_CHECK" /var/lib/libation/inventory.json /var/lib/libation/last-download.log
date -u +%FT%TZ > /var/lib/libation/last-success
