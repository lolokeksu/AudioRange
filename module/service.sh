#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/audiorangectl"
LIB="$MODDIR/common/audiorange-lib.sh"

if [ -f "$LIB" ]; then
    . "$LIB"
    ar_install_cli_wrapper >/dev/null 2>&1 || true
fi

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 180 ]; do
    sleep 2
    i=$((i + 1))
done
sleep 3

if [ -x "$CTL" ]; then
    "$CTL" recover-test >/dev/null 2>&1
    "$CTL" boot-verify >/dev/null 2>&1
fi
