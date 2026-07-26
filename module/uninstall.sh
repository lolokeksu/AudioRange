#!/system/bin/sh

MODDIR=${0%/*}
DATA_DIR="/data/adb/audiorange"
TEST_STATE="$DATA_DIR/test.state"

if [ -f "$TEST_STATE" ]; then
    ORIGINAL="$(sed -n 's/^original=//p' "$TEST_STATE" | tail -n 1)"
    case "$ORIGINAL" in
        ''|*[!0-9]*) ;;
        *)
            if [ -x /system/bin/cmd ]; then
                /system/bin/cmd media_session volume --stream 3 --set "$ORIGINAL" >/dev/null 2>&1
            elif command -v cmd >/dev/null 2>&1; then
                cmd media_session volume --stream 3 --set "$ORIGINAL" >/dev/null 2>&1
            fi
            ;;
    esac
fi

KSU_CLI="/data/adb/ksu/bin/audiorange"
if grep -q '^# AudioRange managed KernelSU wrapper$' "$KSU_CLI" 2>/dev/null; then
    rm -f "$KSU_CLI" 2>/dev/null
fi

rm -rf "$DATA_DIR"
rm -f "$MODDIR/audiorange.log" "$MODDIR/.module.prop.tmp."* 2>/dev/null
# The systemless property and /system/bin/audiorange disappear with the module.
# The OEM/ROM volume configuration returns after the next reboot.
