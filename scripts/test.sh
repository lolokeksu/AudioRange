#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODULE=$ROOT/module

"$ROOT/scripts/generate-manifest.sh"

for file in customize.sh post-fs-data.sh service.sh action.sh uninstall.sh bin/audiorangectl system/bin/audiorange; do
  sh -n "$MODULE/$file"
done
if command -v busybox >/dev/null 2>&1; then
  for file in customize.sh post-fs-data.sh service.sh action.sh uninstall.sh bin/audiorangectl system/bin/audiorange; do
    busybox sh -n "$MODULE/$file"
  done
fi
if command -v node >/dev/null 2>&1; then
  node --check "$MODULE/webroot/app.js"
  node --check "$MODULE/webroot/ksu-bridge.js"
fi
python3 "$ROOT/tests/static_checks.py"
(
  cd "$MODULE"
  sha256sum -c manifest.sha256
)
printf '%s\n' 'All tests passed.'
