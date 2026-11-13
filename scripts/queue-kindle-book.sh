#!/usr/bin/env bash
# Queue an official EPUB/PDF export; the remote timer performs validation/import.
set -euo pipefail
if [ "$#" -ne 2 ] || [[ ! "$1" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Usage: $0 ASIN /path/to/export.epub-or-pdf" >&2
  exit 2
fi
asin=$1
source_file=$(cd -- "$(dirname -- "$2")" && pwd)/$(basename -- "$2")
extension=${source_file##*.}
case "$extension" in epub|pdf) ;; *) echo 'Expected an EPUB or PDF export' >&2; exit 2 ;; esac
[ -f "$source_file" ] && [ ! -L "$source_file" ]
host=ncwade@tycho.tailf3d82.ts.net
# All interpolated remote path components are generated here or restricted above.
nonce=$(uuidgen | tr '[:upper:]' '[:lower:]')
partial="/srv/kindle-inbox/.$asin.$nonce.part"
ssh -o StrictHostKeyChecking=yes "$host" 'test -d /srv/kindle-inbox && test -w /srv/kindle-inbox'
scp -q -o StrictHostKeyChecking=yes "$source_file" "$host:$partial"
ssh -o StrictHostKeyChecking=yes "$host" "chmod 0600 '$partial' && mv -- '$partial' '/srv/kindle-inbox/$asin.$extension'"
echo "Queued $asin.$extension on Tycho. Import runs every five minutes."
