#!/system/bin/sh

# Общая библиотека AudioRange.
# Перед подключением вызывающий скрипт должен определить MODDIR.

AR_VERSION="v1.0.0-beta.1"
AR_MODULE_ID="audiorange"
AR_DATA_DIR="/data/adb/audiorange"
AR_CONFIG="$AR_DATA_DIR/config.conf"
AR_HISTORY="$AR_DATA_DIR/history.log"
AR_STATE="$AR_DATA_DIR/state.conf"
AR_BASELINE="$AR_DATA_DIR/baseline.conf"
AR_TEST_STATE="$AR_DATA_DIR/test.state"
AR_EARLY_STATE="$AR_DATA_DIR/early-apply.conf"
AR_COMPAT="$AR_DATA_DIR/compatibility.conf"
AR_LOCK="$AR_DATA_DIR/run.lock"
AR_SYSTEM_PROP="$MODDIR/system.prop"
AR_MODULE_PROP="$MODDIR/module.prop"
AR_MANIFEST="$MODDIR/manifest.sha256"
AR_DEFAULT_PROFILE="stock"
AR_DEFAULT_CUSTOM="60"
AR_CUSTOM_MIN=15
AR_CUSTOM_MAX=100
AR_MIN_API=33
AR_MAX_API=36

ar_now() {
    date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date
}

ar_epoch() {
    date '+%s' 2>/dev/null || echo 0
}

ar_init_dirs() {
    mkdir -p "$AR_DATA_DIR" 2>/dev/null
    chmod 0700 "$AR_DATA_DIR" 2>/dev/null
}

ar_cfg_get() {
    key="$1"
    file="${2:-$AR_CONFIG}"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$file" 2>/dev/null | tail -n 1
}

ar_propfile_get() {
    key="$1"
    file="$2"
    [ -f "$file" ] || return 0
    sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$file" 2>/dev/null | head -n 1
}

ar_is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

ar_valid_custom() {
    value="$1"
    ar_is_uint "$value" || return 1
    [ "$value" -ge "$AR_CUSTOM_MIN" ] 2>/dev/null && [ "$value" -le "$AR_CUSTOM_MAX" ] 2>/dev/null
}

ar_valid_profile() {
    case "$1" in
        stock|30|50|75|100|custom) return 0 ;;
        *) return 1 ;;
    esac
}

ar_profile_steps() {
    profile="$1"
    custom="$2"
    case "$profile" in
        stock) printf '%s' "" ;;
        30|50|75|100) printf '%s' "$profile" ;;
        custom) printf '%s' "$custom" ;;
        *) return 1 ;;
    esac
}

ar_android_api() {
    value="$(getprop ro.build.version.sdk 2>/dev/null)"
    ar_is_uint "$value" && printf '%s' "$value" || printf '%s' "unknown"
}

ar_android_name() {
    case "$1" in
        33) printf '%s' "Android 13" ;;
        34) printf '%s' "Android 14" ;;
        35) printf '%s' "Android 15" ;;
        36) printf '%s' "Android 16" ;;
        *) printf '%s' "Android неизвестной версии" ;;
    esac
}

ar_android_supported() {
    value="${1:-$(ar_android_api)}"
    ar_is_uint "$value" || return 1
    [ "$value" -ge "$AR_MIN_API" ] 2>/dev/null && [ "$value" -le "$AR_MAX_API" ] 2>/dev/null
}


ar_boot_id() {
    value="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    [ -n "$value" ] && printf '%s' "$value" || printf '%s' "unknown"
}

ar_early_get() {
    ar_cfg_get "$1" "$AR_EARLY_STATE"
}

ar_build_id() {
    value="$(getprop ro.build.fingerprint 2>/dev/null)"
    [ -n "$value" ] || value="$(getprop ro.build.version.incremental 2>/dev/null)"
    [ -n "$value" ] || value="unknown"
    printf '%s' "$value"
}


ar_csv_has() {
    _vch_list="$1"
    _vch_value="$2"
    case ",$_vch_list," in
        *",$_vch_value,"*) return 0 ;;
        *) return 1 ;;
    esac
}

ar_csv_add() {
    _vca_list="$1"
    _vca_value="$2"
    [ -n "$_vca_value" ] || { printf '%s' "$_vca_list"; return; }
    if ar_csv_has "$_vca_list" "$_vca_value"; then
        printf '%s' "$_vca_list"
    elif [ -n "$_vca_list" ]; then
        printf '%s,%s' "$_vca_list" "$_vca_value"
    else
        printf '%s' "$_vca_value"
    fi
}

ar_csv_remove() {
    _vcr_list="$1"
    _vcr_value="$2"
    _vcr_result=""
    _vcr_old_ifs="$IFS"
    IFS=','
    for _vcr_item in $_vcr_list; do
        [ -n "$_vcr_item" ] || continue
        [ "$_vcr_item" = "$_vcr_value" ] && continue
        _vcr_result="$(ar_csv_add "$_vcr_result" "$_vcr_item")"
    done
    IFS="$_vcr_old_ifs"
    printf '%s' "$_vcr_result"
}

ar_csv_max() {
    _vcm_list="$1"
    _vcm_maximum="unknown"
    _vcm_old_ifs="$IFS"
    IFS=','
    for _vcm_item in $_vcm_list; do
        ar_is_uint "$_vcm_item" || continue
        if ! ar_is_uint "$_vcm_maximum" || [ "$_vcm_item" -gt "$_vcm_maximum" ] 2>/dev/null; then
            _vcm_maximum="$_vcm_item"
        fi
    done
    IFS="$_vcm_old_ifs"
    printf '%s' "$_vcm_maximum"
}

ar_csv_valid_steps() {
    _vcv_list="$1"
    [ -n "$_vcv_list" ] || return 0
    _vcv_old_ifs="$IFS"
    IFS=','
    for _vcv_item in $_vcv_list; do
        if ! ar_valid_custom "$_vcv_item"; then
            IFS="$_vcv_old_ifs"
            return 1
        fi
    done
    IFS="$_vcv_old_ifs"
    return 0
}

ar_compat_file_valid() {
    [ -f "$AR_COMPAT" ] || return 1
    _vcf_schema="$(ar_cfg_get schema "$AR_COMPAT")"
    _vcf_build="$(ar_cfg_get build "$AR_COMPAT")"
    _vcf_stock="$(ar_cfg_get stock_max "$AR_COMPAT")"
    _vcf_known="$(ar_cfg_get known_max "$AR_COMPAT")"
    _vcf_source="$(ar_cfg_get source "$AR_COMPAT")"
    _vcf_confirmed="$(ar_cfg_get confirmed_values "$AR_COMPAT")"
    _vcf_rejected="$(ar_cfg_get rejected_values "$AR_COMPAT")"
    _vcf_requested="$(ar_cfg_get last_requested "$AR_COMPAT")"
    _vcf_observed="$(ar_cfg_get last_observed "$AR_COMPAT")"
    [ "$_vcf_schema" = "1" ] || return 1
    [ -n "$_vcf_build" ] || return 1
    case "$_vcf_stock" in unknown|'') ;; *) ar_is_uint "$_vcf_stock" || return 1 ;; esac
    case "$_vcf_known" in unknown|'') ;; *) ar_valid_custom "$_vcf_known" || return 1 ;; esac
    case "$_vcf_source" in unknown|bundled_static|runtime|mixed) ;; *) return 1 ;; esac
    case "$_vcf_requested" in unknown|'') ;; *) ar_valid_custom "$_vcf_requested" || return 1 ;; esac
    case "$_vcf_observed" in unknown|'') ;; *) ar_is_uint "$_vcf_observed" || return 1 ;; esac
    ar_csv_valid_steps "$_vcf_confirmed" || return 1
    ar_csv_valid_steps "$_vcf_rejected" || return 1
    _vcf_old_ifs="$IFS"
    IFS=','
    for _vcf_item in $_vcf_confirmed; do
        [ -n "$_vcf_item" ] || continue
        if ar_csv_has "$_vcf_rejected" "$_vcf_item"; then
            IFS="$_vcf_old_ifs"
            return 1
        fi
    done
    IFS="$_vcf_old_ifs"
    return 0
}

ar_builtin_compat_lookup() {
    _vbl_build="${1:-$(ar_build_id)}"
    AR_BUILTIN_KNOWN_MAX="unknown"
    AR_BUILTIN_SOURCE="unknown"
    AR_BUILTIN_NOTE="Для этой точной сборки встроенного правила нет. Совместимость определяется только фактической проверкой AudioService."
    case "$_vbl_build" in
        'realme/RMX3700/RE585F:13/SKQ1.221119.001/T.135ddd4_1-cd832:user/release-keys')
            AR_BUILTIN_KNOWN_MAX="30"
            AR_BUILTIN_SOURCE="bundled_static"
            AR_BUILTIN_NOTE="Для этой точной сборки RMX3700 статически подтверждён OEM-предел 30: Oplus AudioService принимает media steps только до 30 включительно."
            ;;
    esac
    export AR_BUILTIN_KNOWN_MAX AR_BUILTIN_SOURCE AR_BUILTIN_NOTE
}

ar_compat_write() {
    _vcw_build="$1"
    _vcw_stock="$2"
    _vcw_known="$3"
    _vcw_source="$4"
    _vcw_confirmed="$5"
    _vcw_rejected="$6"
    _vcw_requested="$7"
    _vcw_observed="$8"
    _vcw_note="$9"
    ar_atomic_from_stdin "$AR_COMPAT" 0600 <<EOF_COMPAT
schema=1
build=$_vcw_build
stock_max=$_vcw_stock
known_max=$_vcw_known
source=$_vcw_source
confirmed_values=$_vcw_confirmed
rejected_values=$_vcw_rejected
last_requested=$_vcw_requested
last_observed=$_vcw_observed
updated_at=$(ar_now)
note=$_vcw_note
EOF_COMPAT
}

ar_compat_prepare() {
    ar_init_dirs
    _vcp_current_build="$(ar_build_id)"
    _vcp_saved_build="$(ar_cfg_get build "$AR_COMPAT")"
    if ! ar_compat_file_valid || [ "$_vcp_saved_build" != "$_vcp_current_build" ]; then
        ar_builtin_compat_lookup "$_vcp_current_build"
        _vcp_stock="unknown"
        if [ "$(ar_baseline_state 2>/dev/null)" = "valid" ]; then
            _vcp_candidate="$(ar_baseline_max)"
            ar_is_uint "$_vcp_candidate" && _vcp_stock="$_vcp_candidate"
        fi
        ar_compat_write "$_vcp_current_build" "$_vcp_stock" "$AR_BUILTIN_KNOWN_MAX" "$AR_BUILTIN_SOURCE" "" "" "unknown" "unknown" "$AR_BUILTIN_NOTE"
        ar_history "compat reset build=$_vcp_current_build known_max=$AR_BUILTIN_KNOWN_MAX source=$AR_BUILTIN_SOURCE"
        return
    fi

    ar_builtin_compat_lookup "$_vcp_current_build"
    _vcp_known="$(ar_cfg_get known_max "$AR_COMPAT")"
    if ar_is_uint "$AR_BUILTIN_KNOWN_MAX" && ! ar_is_uint "$_vcp_known"; then
        _vcp_stock="$(ar_cfg_get stock_max "$AR_COMPAT")"
        _vcp_confirmed="$(ar_cfg_get confirmed_values "$AR_COMPAT")"
        _vcp_rejected="$(ar_cfg_get rejected_values "$AR_COMPAT")"
        _vcp_requested="$(ar_cfg_get last_requested "$AR_COMPAT")"
        _vcp_observed="$(ar_cfg_get last_observed "$AR_COMPAT")"
        ar_compat_write "$_vcp_current_build" "${_vcp_stock:-unknown}" "$AR_BUILTIN_KNOWN_MAX" "$AR_BUILTIN_SOURCE" "$_vcp_confirmed" "$_vcp_rejected" "${_vcp_requested:-unknown}" "${_vcp_observed:-unknown}" "$AR_BUILTIN_NOTE"
    fi
}

ar_compat_get() {
    ar_cfg_get "$1" "$AR_COMPAT"
}

ar_compat_source_text() {
    _vcs_source="$1"
    case "$_vcs_source" in
        bundled_static) printf '%s' "встроенный статический анализ точной прошивки" ;;
        runtime) printf '%s' "проверка AudioService на текущей прошивке" ;;
        mixed) printf '%s' "статический анализ и проверка AudioService" ;;
        *) printf '%s' "не определён" ;;
    esac
}

ar_compat_profile_state() {
    _vcps_value="$1"
    ar_is_uint "$_vcps_value" || { echo "unknown"; return; }
    ar_compat_prepare
    _vcps_known="$(ar_compat_get known_max)"
    _vcps_confirmed="$(ar_compat_get confirmed_values)"
    _vcps_rejected="$(ar_compat_get rejected_values)"
    if ar_csv_has "$_vcps_confirmed" "$_vcps_value"; then
        echo "confirmed"
    elif ar_is_uint "$_vcps_known" && [ "$_vcps_value" -gt "$_vcps_known" ] 2>/dev/null; then
        echo "blocked"
    elif ar_csv_has "$_vcps_rejected" "$_vcps_value"; then
        echo "rejected"
    elif ar_is_uint "$_vcps_known" && [ "$_vcps_value" -le "$_vcps_known" ] 2>/dev/null; then
        echo "known_supported"
    else
        echo "untested"
    fi
}


ar_compat_safe_fallback() {
    # Returns "profile|custom|steps". Only runtime-confirmed values are used;
    # otherwise the conservative fallback is the stock profile.
    ar_compat_prepare
    _vcsf_confirmed="$(ar_compat_get confirmed_values)"
    _vcsf_value="$(ar_csv_max "$_vcsf_confirmed")"
    if ar_valid_custom "$_vcsf_value"; then
        case "$_vcsf_value" in
            30|50|75|100) printf '%s|%s|%s' "$_vcsf_value" "$(ar_cfg_get custom_steps)" "$_vcsf_value" ;;
            *) printf '%s|%s|%s' "custom" "$_vcsf_value" "$_vcsf_value" ;;
        esac
    else
        printf '%s|%s|%s' "stock" "$(ar_cfg_get custom_steps)" "stock"
    fi
}

ar_compat_record_stock() {
    _vcrs_maximum="$1"
    ar_is_uint "$_vcrs_maximum" || return 1
    ar_compat_prepare
    _vcrs_build="$(ar_compat_get build)"
    _vcrs_known="$(ar_compat_get known_max)"
    _vcrs_source="$(ar_compat_get source)"
    _vcrs_confirmed="$(ar_compat_get confirmed_values)"
    _vcrs_rejected="$(ar_compat_get rejected_values)"
    _vcrs_requested="$(ar_compat_get last_requested)"
    _vcrs_observed="$(ar_compat_get last_observed)"
    _vcrs_note="$(ar_compat_get note)"
    ar_compat_write "$_vcrs_build" "$_vcrs_maximum" "${_vcrs_known:-unknown}" "${_vcrs_source:-unknown}" "$_vcrs_confirmed" "$_vcrs_rejected" "${_vcrs_requested:-unknown}" "${_vcrs_observed:-unknown}" "$_vcrs_note"
}

ar_compat_record_result() {
    _vcrr_requested="$1"
    _vcrr_observed="$2"
    _vcrr_result="$3"
    ar_is_uint "$_vcrr_requested" || return 1
    ar_compat_prepare
    _vcrr_build="$(ar_compat_get build)"
    _vcrr_stock="$(ar_compat_get stock_max)"
    _vcrr_known="$(ar_compat_get known_max)"
    _vcrr_source="$(ar_compat_get source)"
    _vcrr_confirmed="$(ar_compat_get confirmed_values)"
    _vcrr_rejected="$(ar_compat_get rejected_values)"
    _vcrr_note="$(ar_compat_get note)"
    case "$_vcrr_result" in
        confirmed)
            _vcrr_confirmed="$(ar_csv_add "$_vcrr_confirmed" "$_vcrr_requested")"
            _vcrr_rejected="$(ar_csv_remove "$_vcrr_rejected" "$_vcrr_requested")"
            case "$_vcrr_source" in unknown|'') _vcrr_source="runtime" ;; bundled_static) _vcrr_source="mixed" ;; esac
            ;;
        rejected)
            _vcrr_rejected="$(ar_csv_add "$_vcrr_rejected" "$_vcrr_requested")"
            _vcrr_confirmed="$(ar_csv_remove "$_vcrr_confirmed" "$_vcrr_requested")"
            case "$_vcrr_source" in unknown|'') _vcrr_source="runtime" ;; bundled_static) _vcrr_source="mixed" ;; esac
            ;;
        *) return 1 ;;
    esac
    ar_compat_write "$_vcrr_build" "${_vcrr_stock:-unknown}" "${_vcrr_known:-unknown}" "$_vcrr_source" "$_vcrr_confirmed" "$_vcrr_rejected" "$_vcrr_requested" "${_vcrr_observed:-unknown}" "$_vcrr_note"
    ar_history "compat result=$_vcrr_result requested=$_vcrr_requested observed=${_vcrr_observed:-unknown} build=$_vcrr_build"
}

ar_lock_cleanup() {
    [ -d "$AR_LOCK" ] || return 0
    owner="$(cat "$AR_LOCK/pid" 2>/dev/null)"
    if ! ar_is_uint "$owner" || ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$AR_LOCK" 2>/dev/null
        return 0
    fi
    return 1
}

ar_lock_acquire() {
    ar_init_dirs
    ar_lock_cleanup >/dev/null 2>&1
    tries=0
    while ! mkdir "$AR_LOCK" 2>/dev/null; do
        ar_lock_cleanup >/dev/null 2>&1 && continue
        tries=$((tries + 1))
        [ "$tries" -lt 12 ] || return 1
        sleep 1
    done
    printf '%s\n' "$$" > "$AR_LOCK/pid"
    chmod 0700 "$AR_LOCK" 2>/dev/null
    return 0
}

ar_lock_release() {
    rm -rf "$AR_LOCK" 2>/dev/null
}

ar_atomic_from_stdin() {
    target="$1"
    mode="$2"
    dir="${target%/*}"
    tmp="$dir/.${target##*/}.tmp.$$"
    mkdir -p "$dir" 2>/dev/null || return 1
    cat > "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    chmod "$mode" "$tmp" 2>/dev/null || {
        rm -f "$tmp"
        return 1
    }
    mv -f "$tmp" "$target"
}

ar_state_set() {
    key="$1"
    value="$2"
    ar_init_dirs
    tmp="$AR_DATA_DIR/.state.tmp.$$"
    if [ -f "$AR_STATE" ]; then
        awk -F= -v key="$key" '$1 != key { print }' "$AR_STATE" > "$tmp" 2>/dev/null || : > "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$AR_STATE"
}

ar_state_get() {
    ar_cfg_get "$1" "$AR_STATE"
}

ar_history() {
    event="$*"
    ar_init_dirs
    tmp="$AR_DATA_DIR/.history.tmp.$$"
    if [ -f "$AR_HISTORY" ]; then
        tail -n 199 "$AR_HISTORY" 2>/dev/null > "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s %s\n' "$(ar_now)" "$event" >> "$tmp"
    chmod 0600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$AR_HISTORY" 2>/dev/null
}

ar_write_config() {
    profile="$1"
    custom="$2"
    pending="$3"
    last_applied="$4"
    last_confirmed="$5"
    last_result="$6"
    failures="$7"
    verified_build="$8"
    ar_atomic_from_stdin "$AR_CONFIG" 0600 <<EOF_CFG
schema=3
profile=$profile
custom_steps=$custom
pending_reboot=$pending
last_applied=$last_applied
last_confirmed=$last_confirmed
last_result=$last_result
verification_failures=$failures
last_verified_build=$verified_build
EOF_CFG
}

ar_ensure_config() {
    ar_init_dirs
    profile="$(ar_cfg_get profile)"
    custom="$(ar_cfg_get custom_steps)"
    pending="$(ar_cfg_get pending_reboot)"
    last_applied="$(ar_cfg_get last_applied)"
    last_confirmed="$(ar_cfg_get last_confirmed)"
    last_result="$(ar_cfg_get last_result)"
    failures="$(ar_cfg_get verification_failures)"
    verified_build="$(ar_cfg_get last_verified_build)"

    # Normalize missing or invalid configuration from this standalone project.
    if ! ar_valid_profile "$profile"; then
        profile="$AR_DEFAULT_PROFILE"
        custom="$AR_DEFAULT_CUSTOM"
        pending=0
        last_applied="stock"
        last_confirmed="unknown"
        last_result="new"
    fi

    ar_valid_custom "$custom" || custom="$AR_DEFAULT_CUSTOM"
    case "$pending" in 0|1) ;; *) pending=0 ;; esac
    ar_is_uint "$failures" || failures=0
    [ -n "$last_applied" ] || last_applied="unknown"
    [ -n "$last_confirmed" ] || last_confirmed="unknown"
    [ -n "$last_result" ] || last_result="unknown"
    [ -n "$verified_build" ] || verified_build="unknown"

    ar_write_config "$profile" "$custom" "$pending" "$last_applied" "$last_confirmed" "$last_result" "$failures" "$verified_build"
}

ar_system_prop_content() {
    profile="$1"
    custom="$2"
    steps="$(ar_profile_steps "$profile" "$custom")" || return 1
    if [ "$profile" = "stock" ]; then
        cat <<'EOF_PROP'
# AudioRange: штатный профиль.
# Модуль не переопределяет ro.config.media_vol_steps.
EOF_PROP
    else
        cat <<EOF_PROP
# AudioRange: пользовательский профиль.
ro.config.media_vol_steps=$steps
EOF_PROP
    fi
}

ar_render_system_prop() {
    profile="$1"
    custom="$2"
    ar_system_prop_content "$profile" "$custom" | ar_atomic_from_stdin "$AR_SYSTEM_PROP" 0644
}

ar_root_manager() {
    if [ -n "${APATCH_VER_CODE:-}" ] || [ -d /data/adb/ap ] || command -v apd >/dev/null 2>&1; then
        echo "APatch"
    elif [ -n "${KSU_VER_CODE:-}" ] || [ -d /data/adb/ksu ] || command -v ksud >/dev/null 2>&1; then
        echo "KernelSU"
    elif command -v magisk >/dev/null 2>&1 || [ -d /data/adb/magisk ]; then
        echo "Magisk"
    else
        echo "Unknown"
    fi
}


ar_ksu_cli_path() {
    printf '%s' "/data/adb/ksu/bin/audiorange"
}

ar_install_cli_wrapper() {
    [ "$(ar_root_manager)" = "KernelSU" ] || return 0
    target="$(ar_ksu_cli_path)"
    dir="${target%/*}"
    tmp="$dir/.audiorange.tmp.$$"
    mkdir -p "$dir" 2>/dev/null || return 1
    if [ -e "$target" ] && ! grep -q '^# AudioRange managed KernelSU wrapper$' "$target" 2>/dev/null; then
        return 2
    fi
    cat > "$tmp" <<'EOF_AR_CLI'
#!/system/bin/sh
# AudioRange managed KernelSU wrapper
CTL="/data/adb/modules/audiorange/bin/audiorangectl"
[ -x "$CTL" ] || { echo "Ошибка: контроллер AudioRange недоступен." >&2; exit 1; }
exec "$CTL" "$@"
EOF_AR_CLI
    chmod 0755 "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

ar_remove_cli_wrapper() {
    target="$(ar_ksu_cli_path)"
    if grep -q '^# AudioRange managed KernelSU wrapper$' "$target" 2>/dev/null; then
        rm -f "$target" 2>/dev/null
    fi
}

ar_runtime_cli_path() {
    if [ -x /system/bin/audiorange ]; then
        printf '%s' "/system/bin/audiorange"
        return 0
    fi
    target="$(ar_ksu_cli_path)"
    if [ -x "$target" ]; then
        printf '%s' "$target"
        return 0
    fi
    return 1
}

ar_prop_first() {
    for key in "$@"; do
        value="$(getprop "$key" 2>/dev/null | head -n 1)"
        [ -n "$value" ] && { printf '%s' "$value"; return 0; }
    done
    return 1
}

ar_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

ar_rom_detect() {
    brand="$(ar_lower "$(ar_prop_first ro.product.brand ro.product.system.brand ro.product.vendor.brand)")"
    manufacturer="$(ar_lower "$(ar_prop_first ro.product.manufacturer ro.product.system.manufacturer ro.product.vendor.manufacturer)")"
    realme_ver="$(ar_prop_first ro.build.version.realmeui ro.realme.version)"
    oxygen_ver="$(ar_prop_first ro.oxygen.version ro.build.version.oxygen ro.oxygen.version.display)"
    oplus_ver="$(ar_prop_first ro.build.version.oplusrom ro.build.version.opporom ro.oplus.version)"
    hyper_ver="$(ar_prop_first ro.mi.os.version.name ro.build.version.hyperos ro.mi.os.version.incremental)"
    miui_ver="$(ar_prop_first ro.miui.ui.version.name ro.miui.ui.version.code)"
    oneui_ver="$(ar_prop_first ro.build.version.oneui ro.build.version.sem)"
    nothing_ver="$(ar_prop_first ro.nothing.version ro.build.version.nothing)"
    vivo_ver="$(ar_prop_first ro.vivo.os.version ro.vivo.os.name ro.originos.version)"
    magic_ver="$(ar_prop_first ro.build.version.magic ro.build.version.magicui)"
    emui_ver="$(ar_prop_first ro.build.version.emui ro.build.version.magicui)"

    AR_ROM_FAMILY="generic"
    AR_ROM_NAME="Неопределённая Android-оболочка"
    AR_ROM_VERSION="unknown"
    AR_ROM_CONFIDENCE="low"
    AR_ROM_NOTICE="Внутренняя реализация оболочки не определена. Совместимость оценивается только по фактическому диапазону AudioService."
    AR_ROM_SCOPE="логический диапазон мультимедиа STREAM_MUSIC в Android Framework"
    AR_ROM_OUTSIDE="усиление, кривые Audio Policy, OEM-микшеры, аудиоэффекты и аппаратные уровни Bluetooth"

    case "$brand:$manufacturer" in
        *realme*|*:realme*)
            AR_ROM_FAMILY="realmeui"; AR_ROM_NAME="Realme UI"; AR_ROM_VERSION="${realme_ver:-$oplus_ver}"
            [ -n "$realme_ver" ] && AR_ROM_CONFIDENCE="high" || AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="Ultra Volume и OReality/Dirac могут менять усиление и обработку сигнала. Они не подтверждают и не отменяют изменение логического диапазона Android."
            ;;
        *oneplus*|*:oneplus*)
            AR_ROM_FAMILY="oxygenos"; AR_ROM_NAME="OxygenOS"; AR_ROM_VERSION="${oxygen_ver:-$oplus_ver}"
            [ -n "$oxygen_ver$oplus_ver" ] && AR_ROM_CONFIDENCE="high" || AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="Holo Audio, Dolby и маршрутизация OnePlus работают поверх системной шкалы и модулем не изменяются."
            ;;
        *oppo*|*:oppo*)
            AR_ROM_FAMILY="coloros"; AR_ROM_NAME="ColorOS"; AR_ROM_VERSION="$oplus_ver"
            [ -n "$oplus_ver" ] && AR_ROM_CONFIDENCE="high" || AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="OReality, Dolby и OEM Audio Policy могут менять кривую громкости. Подтверждением профиля остаётся диапазон AudioService."
            ;;
        *xiaomi*|*redmi*|*poco*|*:xiaomi*|*:redmi*|*:poco*)
            if [ -n "$hyper_ver" ]; then
                AR_ROM_FAMILY="hyperos"; AR_ROM_NAME="Xiaomi HyperOS"; AR_ROM_VERSION="$hyper_ver"; AR_ROM_CONFIDENCE="high"
            elif [ -n "$miui_ver" ]; then
                AR_ROM_FAMILY="miui"; AR_ROM_NAME="MIUI"; AR_ROM_VERSION="$miui_ver"; AR_ROM_CONFIDENCE="high"
            else
                AR_ROM_FAMILY="xiaomi"; AR_ROM_NAME="Xiaomi ROM"; AR_ROM_CONFIDENCE="medium"
            fi
            AR_ROM_NOTICE="Sound Assistant, Game Turbo и громкость отдельных приложений работают поверх глобальной шкалы и модулем не изменяются."
            ;;
        *samsung*|*:samsung*)
            AR_ROM_FAMILY="oneui"; AR_ROM_NAME="Samsung One UI"; AR_ROM_VERSION="$oneui_ver"
            [ -n "$oneui_ver" ] && AR_ROM_CONFIDENCE="high" || AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="Sound Assistant может отдельно менять шаг кнопок, а Separate App Sound — маршрутизацию. Для чистой проверки отключите изменение шага в Sound Assistant."
            ;;
        *motorola*|*:motorola*)
            AR_ROM_FAMILY="motorola"; AR_ROM_NAME="Motorola My UX / Hello UI"; AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="Multi-volume регулирует отдельные приложения поверх системной шкалы и модулем не изменяется."
            ;;
        *google*|*:google*)
            AR_ROM_FAMILY="pixel"; AR_ROM_NAME="Google Pixel UI / AOSP"; AR_ROM_CONFIDENCE="high"
            AR_ROM_NOTICE="Архитектура близка к AOSP, поэтому поведение свойства обычно наиболее предсказуемо. Итог всё равно проверяется через AudioService."
            ;;
        *nothing*|*:nothing*)
            AR_ROM_FAMILY="nothingos"; AR_ROM_NAME="Nothing OS"; AR_ROM_VERSION="$nothing_ver"; AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="Оболочка близка к AOSP, но SystemUI и Audio Policy могут отдельно менять визуальный шаг и кривую громкости."
            ;;
        *asus*|*rog*|*:asus*)
            AR_ROM_FAMILY="asus"; AR_ROM_NAME="ASUS ZenUI / ROG UI"; AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="AudioWizard и игровые профили меняют обработку выхода, но не логический диапазон, которым управляет модуль."
            ;;
        *vivo*|*iqoo*|*:vivo*|*:iqoo*)
            AR_ROM_FAMILY="vivo"; AR_ROM_NAME="Funtouch OS / OriginOS"; AR_ROM_VERSION="$vivo_ver"; AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="Реализация AudioService закрыта. Фактическая поддержка определяется только проверкой после загрузки."
            ;;
        *honor*|*:honor*)
            AR_ROM_FAMILY="magicos"; AR_ROM_NAME="Honor MagicOS"; AR_ROM_VERSION="${magic_ver:-$emui_ver}"; AR_ROM_CONFIDENCE="medium"
            AR_ROM_NOTICE="OEM-аудиостек закрыт. Фирменные эффекты, маршрутизация и кривые усиления модулем не изменяются."
            ;;
        *huawei*|*:huawei*)
            AR_ROM_FAMILY="huawei"; AR_ROM_NAME="Huawei EMUI / HarmonyOS"; AR_ROM_VERSION="$emui_ver"; AR_ROM_CONFIDENCE="low"
            AR_ROM_NOTICE="Root-среда и AudioService могут значительно отличаться от обычного Android. Успешность нельзя предполагать без фактической проверки."
            ;;
    esac

    if [ "$AR_ROM_FAMILY" = "generic" ]; then
        case "$manufacturer" in
            *sony*) AR_ROM_FAMILY="sony"; AR_ROM_NAME="Sony Xperia UI"; AR_ROM_CONFIDENCE="medium" ;;
            *zte*|*nubia*) AR_ROM_FAMILY="zte"; AR_ROM_NAME="ZTE / nubia UI"; AR_ROM_CONFIDENCE="medium" ;;
        esac
    fi

    [ -n "$AR_ROM_VERSION" ] || AR_ROM_VERSION="unknown"
    export AR_ROM_FAMILY AR_ROM_NAME AR_ROM_VERSION AR_ROM_CONFIDENCE AR_ROM_NOTICE AR_ROM_SCOPE AR_ROM_OUTSIDE
}

ar_audio_probe() {
    AR_AUDIO_RAW=""
    AR_AUDIO_CURRENT=""
    AR_AUDIO_MIN=""
    AR_AUDIO_MAX=""
    AR_AUDIO_BACKEND="unavailable"
    AR_AUDIO_CONFIDENCE="none"

    if [ -x /system/bin/cmd ]; then
        AR_AUDIO_RAW="$(/system/bin/cmd media_session volume --stream 3 --get 2>&1)"
    elif command -v cmd >/dev/null 2>&1; then
        AR_AUDIO_RAW="$(cmd media_session volume --stream 3 --get 2>&1)"
    else
        export AR_AUDIO_RAW AR_AUDIO_CURRENT AR_AUDIO_MIN AR_AUDIO_MAX AR_AUDIO_BACKEND AR_AUDIO_CONFIDENCE
        return 1
    fi

    AR_AUDIO_CURRENT="$(printf '%s\n' "$AR_AUDIO_RAW" | sed -n 's/.*volume[[:space:]]*is[[:space:]]*[:=]*[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -n 1)"
    AR_AUDIO_MIN="$(printf '%s\n' "$AR_AUDIO_RAW" | sed -n 's/.*range[[:space:]]*\[[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\.\.[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\].*/\1/p' | tail -n 1)"
    AR_AUDIO_MAX="$(printf '%s\n' "$AR_AUDIO_RAW" | sed -n 's/.*range[[:space:]]*\[[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\.\.[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\].*/\2/p' | tail -n 1)"

    if ar_is_uint "$AR_AUDIO_CURRENT" && ar_is_uint "$AR_AUDIO_MIN" && ar_is_uint "$AR_AUDIO_MAX" \
        && [ "$AR_AUDIO_MIN" -le "$AR_AUDIO_CURRENT" ] 2>/dev/null \
        && [ "$AR_AUDIO_CURRENT" -le "$AR_AUDIO_MAX" ] 2>/dev/null \
        && [ "$AR_AUDIO_MIN" -le "$AR_AUDIO_MAX" ] 2>/dev/null; then
        AR_AUDIO_BACKEND="cmd_media_session"
        AR_AUDIO_CONFIDENCE="high"
        export AR_AUDIO_RAW AR_AUDIO_CURRENT AR_AUDIO_MIN AR_AUDIO_MAX AR_AUDIO_BACKEND AR_AUDIO_CONFIDENCE
        return 0
    fi

    export AR_AUDIO_RAW AR_AUDIO_CURRENT AR_AUDIO_MIN AR_AUDIO_MAX AR_AUDIO_BACKEND AR_AUDIO_CONFIDENCE
    return 1
}

ar_audio_raw() {
    ar_audio_probe >/dev/null 2>&1
    printf '%s' "$AR_AUDIO_RAW"
}

ar_audio_current() {
    raw="$1"
    printf '%s\n' "$raw" | sed -n 's/.*volume[[:space:]]*is[[:space:]]*[:=]*[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -n 1
}

ar_audio_min() {
    raw="$1"
    printf '%s\n' "$raw" | sed -n 's/.*range[[:space:]]*\[[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\.\.[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\].*/\1/p' | tail -n 1
}

ar_audio_max() {
    raw="$1"
    printf '%s\n' "$raw" | sed -n 's/.*range[[:space:]]*\[[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\.\.[[:space:]]*\([0-9][0-9]*\)[[:space:]]*\].*/\2/p' | tail -n 1
}

ar_audio_set() {
    index="$1"
    ar_is_uint "$index" || return 1
    if [ -x /system/bin/cmd ]; then
        /system/bin/cmd media_session volume --stream 3 --set "$index" >/dev/null 2>&1
    elif command -v cmd >/dev/null 2>&1; then
        cmd media_session volume --stream 3 --set "$index" >/dev/null 2>&1
    else
        return 1
    fi
}

ar_prop_value() {
    value="$(getprop ro.config.media_vol_steps 2>/dev/null)"
    [ -n "$value" ] && printf '%s' "$value" || printf '%s' "unset"
}

ar_verification() {
    profile="$1"
    custom="$2"
    pending="$3"
    prop="$4"
    audio_max="$5"
    expected="$(ar_profile_steps "$profile" "$custom")"

    if [ "$profile" = "stock" ]; then
        if [ "$pending" = "1" ]; then
            echo "REBOOT_REQUIRED"
        elif ar_is_uint "$audio_max"; then
            echo "STOCK_ACTIVE"
        else
            echo "STOCK_UNVERIFIED"
        fi
        return
    fi

    if [ "$pending" = "1" ] && [ "$prop" != "$expected" ]; then
        echo "REBOOT_REQUIRED"
    elif [ "$prop" != "$expected" ]; then
        echo "PROPERTY_MISMATCH"
    elif ar_is_uint "$audio_max" && [ "$audio_max" = "$expected" ]; then
        echo "CONFIRMED"
    elif ar_is_uint "$audio_max"; then
        echo "AUDIOSERVICE_MISMATCH"
    else
        echo "PROPERTY_ONLY"
    fi
}

ar_capture_baseline() {
    ar_ensure_config
    profile="$(ar_cfg_get profile)"
    pending="$(ar_cfg_get pending_reboot)"
    [ "$profile" = "stock" ] || return 2
    [ "$pending" = "0" ] || return 3
    ar_audio_probe || return 4
    property="$(ar_prop_value)"
    build="$(ar_build_id)"
    ar_atomic_from_stdin "$AR_BASELINE" 0600 <<EOF_BASELINE
schema=1
property=$property
audio_min=$AR_AUDIO_MIN
audio_max=$AR_AUDIO_MAX
backend=$AR_AUDIO_BACKEND
confidence=$AR_AUDIO_CONFIDENCE
build=$build
captured_at=$(ar_now)
EOF_BASELINE
    ar_history "baseline captured property=$property range=$AR_AUDIO_MIN..$AR_AUDIO_MAX backend=$AR_AUDIO_BACKEND"
    return 0
}

ar_baseline_state() {
    [ -f "$AR_BASELINE" ] || { echo "missing"; return; }
    saved_build="$(ar_cfg_get build "$AR_BASELINE")"
    current_build="$(ar_build_id)"
    if [ -n "$saved_build" ] && [ "$saved_build" != "$current_build" ]; then
        echo "stale"
    else
        echo "valid"
    fi
}

ar_baseline_max() {
    value="$(ar_cfg_get audio_max "$AR_BASELINE")"
    [ -n "$value" ] && printf '%s' "$value" || printf '%s' "unknown"
}

ar_recover_test() {
    [ -f "$AR_TEST_STATE" ] || return 0
    original="$(ar_cfg_get original "$AR_TEST_STATE")"
    if ar_is_uint "$original" && ar_audio_set "$original"; then
        rm -f "$AR_TEST_STATE"
        stamp="restored_$(ar_epoch)_index_$original"
        ar_state_set last_test_recovery "$stamp"
        ar_history "volume_test recovered_after_interruption index=$original"
        echo "Восстановлена громкость прерванного теста: $original."
        return 0
    fi
    ar_state_set last_test_recovery "failed_$(ar_epoch)"
    return 1
}

ar_test_active() {
    [ -f "$AR_TEST_STATE" ] || { echo 0; return; }
    active="$(ar_cfg_get active "$AR_TEST_STATE")"
    [ "$active" = "1" ] && echo 1 || echo 0
}

ar_test_remaining() {
    [ -f "$AR_TEST_STATE" ] || { echo 0; return; }
    expires="$(ar_cfg_get expires "$AR_TEST_STATE")"
    now="$(ar_epoch)"
    if ar_is_uint "$expires" && ar_is_uint "$now" && [ "$expires" -gt "$now" ]; then
        echo $((expires - now))
    else
        echo 0
    fi
}

ar_sha256_file() {
    file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v toybox >/dev/null 2>&1; then
        toybox sha256sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v busybox >/dev/null 2>&1; then
        busybox sha256sum "$file" 2>/dev/null | awk '{print $1}'
    else
        return 1
    fi
}

ar_verify_manifest() {
    ar_manifest_failures=0
    AR_MANIFEST_FAILURES=0
    export AR_MANIFEST_FAILURES
    [ -f "$AR_MANIFEST" ] || {
        echo "[FAIL] manifest.sha256 is missing"
        AR_INTEGRITY="MISSING"
        AR_MANIFEST_FAILURES=1
        export AR_INTEGRITY AR_MANIFEST_FAILURES
        return 1
    }
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        set -- $line
        expected="$1"
        relative="$2"
        file="$MODDIR/$relative"
        if [ ! -f "$file" ]; then
            echo "[FAIL] missing $relative"
            ar_manifest_failures=$((ar_manifest_failures + 1))
            continue
        fi
        actual="$(ar_sha256_file "$file")"
        if [ -n "$actual" ] && [ "$actual" = "$expected" ]; then
            echo "[OK] $relative"
        else
            echo "[FAIL] checksum mismatch: $relative"
            ar_manifest_failures=$((ar_manifest_failures + 1))
        fi
    done < "$AR_MANIFEST"
    AR_MANIFEST_FAILURES="$ar_manifest_failures"
    export AR_MANIFEST_FAILURES
    if [ "$ar_manifest_failures" -eq 0 ]; then
        AR_INTEGRITY="VERIFIED"
        export AR_INTEGRITY
        return 0
    fi
    AR_INTEGRITY="MODIFIED"
    export AR_INTEGRITY
    return 1
}

ar_update_description() {
    ar_desc_status="$1"
    ar_desc_profile="$2"
    ar_desc_value="$3"
    ar_desc_conflicts="$4"
    [ -f "$AR_MODULE_PROP" ] || return 0
    if [ "$ar_desc_profile" = "stock" ]; then ar_desc_selected="Штатный"; else ar_desc_selected="$ar_desc_value шагов"; fi
    case "$ar_desc_status" in
        CONFIRMED) ar_desc_result="подтверждено AudioService" ;;
        STOCK_ACTIVE) ar_desc_result="штатная шкала активна" ;;
        REBOOT_REQUIRED) ar_desc_result="требуется перезагрузка" ;;
        PROPERTY_ONLY) ar_desc_result="свойство применено, диапазон не прочитан" ;;
        PROPERTY_MISMATCH) ar_desc_result="свойство не совпадает" ;;
        AUDIOSERVICE_MISMATCH) ar_desc_result="диапазон AudioService не совпадает" ;;
        STOCK_UNVERIFIED) ar_desc_result="штатный диапазон не прочитан" ;;
        *) ar_desc_result="$ar_desc_status" ;;
    esac
    case "$ar_desc_conflicts" in
        0) ar_desc_conflict_text="конфликтов нет" ;;
        pending) ar_desc_conflict_text="конфликты будут проверены после загрузки" ;;
        *) ar_desc_conflict_text="конфликтов: $ar_desc_conflicts" ;;
    esac
    ar_desc="$ar_desc_selected | $ar_desc_result | $ar_desc_conflict_text"
    ar_desc_tmp="$MODDIR/.module.prop.tmp.$$"
    awk -v desc="$ar_desc" '
        BEGIN { done=0 }
        /^description=/ { if (!done) { print "description=" desc; done=1 }; next }
        { print }
        END { if (!done) print "description=" desc }
    ' "$AR_MODULE_PROP" > "$ar_desc_tmp" && mv -f "$ar_desc_tmp" "$AR_MODULE_PROP"
    chmod 0644 "$AR_MODULE_PROP" 2>/dev/null
}

ar_conflicts_scan() {
    ar_init_dirs
    ar_ensure_config
    profile="$(ar_cfg_get profile)"
    custom="$(ar_cfg_get custom_steps)"
    target="$(ar_profile_steps "$profile" "$custom")"
    [ -n "$target" ] || target="stock"
    base="$AR_DATA_DIR/.conflicts.$$"
    high_keys="$base.high"
    med_keys="$base.med"
    low_keys="$base.low"
    all_keys="$base.all"
    : > "$high_keys"; : > "$med_keys"; : > "$low_keys"; : > "$all_keys"
    AR_CONFLICT_LINES=0
    AR_INFO_LINES=0

    ar_scan_one_file() {
        file="$1"
        source_id="$2"
        source_name="$3"
        [ -f "$file" ] || return 0
        case "$file" in */module.prop) return 0 ;; esac
        size="$(wc -c < "$file" 2>/dev/null)"
        ar_is_uint "$size" || size=0
        [ "$size" -le 524288 ] || return 0
        matches="$base.matches"
        LC_ALL=C grep -n -E 'ro[.]config[.](media|music)_vol_steps' "$file" 2>/dev/null > "$matches"
        [ -s "$matches" ] || { rm -f "$matches"; return 0; }
        while IFS= read -r record || [ -n "$record" ]; do
            line_no="${record%%:*}"
            text="${record#*:}"
            trimmed="$(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
            case "$trimmed" in \#*) continue ;; esac
            severity="INFO"
            value="unknown"
            reason="mention"
            property="media"
            printf '%s' "$text" | grep -q 'ro[.]config[.]music_vol_steps' && property="music"

            direct="$(printf '%s\n' "$text" | sed -n 's/.*ro[.]config[.]media_vol_steps[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -n 1)"
            command_value="$(printf '%s\n' "$text" | sed -n 's/.*\(resetprop\|setprop\)[^#;]*ro[.]config[.]media_vol_steps[[:space:]]\+\([^[:space:];#]*\).*/\2/p' | tail -n 1)"
            if [ "$property" = "music" ]; then
                severity="MEDIUM"
                reason="legacy_property"
                echo "$source_id" >> "$med_keys"
                echo "$source_id" >> "$all_keys"
            elif ar_is_uint "$direct"; then
                value="$direct"
                if [ "$target" = "stock" ] || [ "$value" != "$target" ]; then
                    severity="HIGH"; reason="different_literal"; echo "$source_id" >> "$high_keys"; echo "$source_id" >> "$all_keys"
                else
                    severity="LOW"; reason="duplicate_literal"; echo "$source_id" >> "$low_keys"
                fi
            elif ar_is_uint "$command_value"; then
                value="$command_value"
                if [ "$target" = "stock" ] || [ "$value" != "$target" ]; then
                    severity="HIGH"; reason="different_runtime_value"; echo "$source_id" >> "$high_keys"; echo "$source_id" >> "$all_keys"
                else
                    severity="LOW"; reason="duplicate_runtime_value"; echo "$source_id" >> "$low_keys"
                fi
            elif printf '%s' "$text" | grep -Eq '(^|[[:space:];])(resetprop|setprop)([[:space:]]+-[^[:space:]]+)*[[:space:]]+ro[.]config[.]media_vol_steps'; then
                value="dynamic"
                severity="MEDIUM"; reason="dynamic_runtime_value"; echo "$source_id" >> "$med_keys"; echo "$source_id" >> "$all_keys"
            elif printf '%s' "$text" | grep -Eq 'ro[.]config[.]media_vol_steps[[:space:]]*='; then
                value="dynamic"
                severity="MEDIUM"; reason="dynamic_property"; echo "$source_id" >> "$med_keys"; echo "$source_id" >> "$all_keys"
            else
                AR_INFO_LINES=$((AR_INFO_LINES + 1))
            fi

            if [ "$severity" != "INFO" ]; then
                AR_CONFLICT_LINES=$((AR_CONFLICT_LINES + 1))
            fi
            case "$reason" in
                different_literal) reason_text="другое значение в property-файле" ;;
                different_runtime_value) reason_text="другое значение задаётся скриптом" ;;
                duplicate_literal) reason_text="совпадающее значение в property-файле" ;;
                duplicate_runtime_value) reason_text="совпадающее значение задаётся скриптом" ;;
                dynamic_runtime_value) reason_text="значение вычисляется скриптом и заранее неизвестно" ;;
                dynamic_property) reason_text="значение свойства вычисляется динамически" ;;
                legacy_property) reason_text="используется устаревшее свойство music_vol_steps" ;;
                *) reason_text="$reason" ;;
            esac
            case "$severity" in
                HIGH) severity_text="КРИТИЧЕСКИЙ" ;;
                MEDIUM) severity_text="ДИНАМИЧЕСКИЙ" ;;
                LOW) severity_text="СОВПАДЕНИЕ" ;;
                *) severity_text="$severity" ;;
            esac
            printf '[%s] %s [%s]\n' "$severity_text" "$source_name" "$source_id"
            printf '  Файл: %s:%s\n' "$file" "$line_no"
            printf '  Значение: %s; наш профиль: %s\n' "$value" "$target"
            printf '  Причина: %s\n' "$reason_text"
        done < "$matches"
        rm -f "$matches"
    }

    for dir in /data/adb/modules/*; do
        [ -d "$dir" ] || continue
        [ "$dir" = "$MODDIR" ] && continue
        [ "${dir##*/}" = "$AR_MODULE_ID" ] && continue
        [ -f "$dir/disable" ] && continue
        [ -f "$dir/remove" ] && continue
        source_id="$(ar_propfile_get id "$dir/module.prop")"
        [ -n "$source_id" ] || source_id="${dir##*/}"
        source_name="$(ar_propfile_get name "$dir/module.prop")"
        [ -n "$source_name" ] || source_name="$source_id"
        for file in "$dir/service.sh" "$dir/post-fs-data.sh" "$dir/boot-completed.sh" "$dir/post-mount.sh" "$dir/action.sh" "$dir/customize.sh" "$dir"/*.prop "$dir"/*.conf "$dir"/common/*.sh "$dir"/scripts/*.sh; do
            ar_scan_one_file "$file" "$source_id" "$source_name"
        done
    done

    for file in /data/adb/service.d/* /data/adb/post-fs-data.d/* /data/adb/boot-completed.d/*; do
        [ -f "$file" ] || continue
        source_id="global:${file##*/}"
        ar_scan_one_file "$file" "$source_id" "Global root script"
    done

    AR_CONFLICT_HIGH="$(sort -u "$high_keys" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
    AR_CONFLICT_MEDIUM="$(sort -u "$med_keys" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
    AR_CONFLICT_LOW="$(sort -u "$low_keys" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
    ar_is_uint "$AR_CONFLICT_HIGH" || AR_CONFLICT_HIGH=0
    ar_is_uint "$AR_CONFLICT_MEDIUM" || AR_CONFLICT_MEDIUM=0
    ar_is_uint "$AR_CONFLICT_LOW" || AR_CONFLICT_LOW=0
    AR_CONFLICT_COUNT="$(sort -u "$all_keys" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
    ar_is_uint "$AR_CONFLICT_COUNT" || AR_CONFLICT_COUNT=0
    export AR_CONFLICT_HIGH AR_CONFLICT_MEDIUM AR_CONFLICT_LOW AR_CONFLICT_COUNT AR_CONFLICT_LINES AR_INFO_LINES
    rm -f "$high_keys" "$med_keys" "$low_keys" "$all_keys" "$base.matches"
}

ar_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/\\r/g; s/\t/\\t/g'
}
