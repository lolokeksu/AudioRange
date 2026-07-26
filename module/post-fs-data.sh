#!/system/bin/sh

# Раннее применение выбранного диапазона до запуска Zygote/AudioService.
# Скрипт намеренно минимален: без ожиданий, сети и обращения к Android-сервисам.

MODDIR=${0%/*}
PROP_FILE="$MODDIR/system.prop"
DATA_DIR="/data/adb/audiorange"
STATE_FILE="$DATA_DIR/early-apply.conf"
PROP_NAME="ro.config.media_vol_steps"

ar_early_write_state() {
    result="$1"
    target="$2"
    before="$3"
    after="$4"
    boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    mkdir -p "$DATA_DIR" 2>/dev/null || return 0
    chmod 0700 "$DATA_DIR" 2>/dev/null
    tmp="$DATA_DIR/.early-apply.tmp.$$"
    umask 077
    cat > "$tmp" <<EOF_STATE
schema=1
result=$result
target=$target
property_before=$before
property_after=$after
boot_id=${boot_id:-unknown}
EOF_STATE
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

before="$(getprop "$PROP_NAME" 2>/dev/null)"
steps="$(sed -n 's/^[[:space:]]*ro\.config\.media_vol_steps[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$PROP_FILE" 2>/dev/null | tail -n 1)"

# Штатный профиль не должен создавать или удалять read-only property.
if [ -z "$steps" ]; then
    ar_early_write_state "stock_skipped" "stock" "$before" "$before"
    exit 0
fi

case "$steps" in
    ''|*[!0-9]*)
        ar_early_write_state "invalid_value" "$steps" "$before" "$before"
        exit 0
        ;;
esac
if [ "$steps" -lt 15 ] 2>/dev/null || [ "$steps" -gt 100 ] 2>/dev/null; then
    ar_early_write_state "invalid_value" "$steps" "$before" "$before"
    exit 0
fi

if ! command -v resetprop >/dev/null 2>&1; then
    ar_early_write_state "resetprop_missing" "$steps" "$before" "$before"
    exit 0
fi

if resetprop -n "$PROP_NAME" "$steps" >/dev/null 2>&1; then
    after="$(getprop "$PROP_NAME" 2>/dev/null)"
    if [ "$after" = "$steps" ]; then
        ar_early_write_state "applied" "$steps" "$before" "$after"
    else
        ar_early_write_state "property_mismatch" "$steps" "$before" "$after"
    fi
else
    after="$(getprop "$PROP_NAME" 2>/dev/null)"
    ar_early_write_state "resetprop_failed" "$steps" "$before" "$after"
fi

# Ошибка раннего применения не должна блокировать загрузку Android.
exit 0
