#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODULE=$ROOT/module
OUT=$MODULE/manifest.sha256
FILES='LICENSE
CHANGELOG.md
post-fs-data.sh
service.sh
action.sh
uninstall.sh
bin/audiorangectl
common/audiorange-lib.sh
system/bin/audiorange
webroot/index.html
webroot/app.js
webroot/ksu-bridge.js
webroot/style.css
banner.png
webicon.png'
: > "$OUT.tmp"
printf '%s\n' "$FILES" | while IFS= read -r file; do
  [ -f "$MODULE/$file" ] || { echo "Missing manifest file: $file" >&2; exit 1; }
  hash=$(sha256sum "$MODULE/$file" | awk '{print $1}')
  printf '%s  %s\n' "$hash" "$file" >> "$OUT.tmp"
done
mv -f "$OUT.tmp" "$OUT"
