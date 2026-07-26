#!/system/bin/sh

SKIPUNZIP=0

ui_print "***********************************"
ui_print "       AudioRange"
ui_print "  v1.0.0-beta.1 by Lolokeksu"
ui_print "***********************************"

API_LEVEL="${API:-$(getprop ro.build.version.sdk 2>/dev/null)}"
case "$API_LEVEL" in
    ''|*[!0-9]*) abort "! Не удалось определить версию Android API" ;;
esac
if [ "$API_LEVEL" -lt 33 ] || [ "$API_LEVEL" -gt 36 ]; then
    abort "! Поддерживаются только Android 13–16 / API 33–36 (обнаружен API $API_LEVEL)"
fi
case "$API_LEVEL" in
    33) ANDROID_NAME="Android 13" ;;
    34) ANDROID_NAME="Android 14" ;;
    35) ANDROID_NAME="Android 15" ;;
    36) ANDROID_NAME="Android 16" ;;
esac

MODDIR="$MODPATH"
LIB="$MODPATH/common/audiorange-lib.sh"
[ -f "$LIB" ] || abort "! Не найден общий файл логики модуля"
. "$LIB"

# Standalone project: only the current module data directory is used.
ar_init_dirs
ar_ensure_config
ar_compat_prepare
PROFILE="$(ar_cfg_get profile)"
CUSTOM="$(ar_cfg_get custom_steps)"

# Do not carry a profile already known to be incompatible into the next boot.
# The fallback is the highest runtime-confirmed value for this exact fingerprint,
# or the stock profile when no runtime-confirmed value exists.
if [ "$PROFILE" != "stock" ]; then
    PROFILE_STEPS="$(ar_profile_steps "$PROFILE" "$CUSTOM")"
    PROFILE_STATE="$(ar_compat_profile_state "$PROFILE_STEPS")"
    case "$PROFILE_STATE" in
        blocked|rejected)
            FALLBACK="$(ar_compat_safe_fallback)"
            FALLBACK_PROFILE="${FALLBACK%%|*}"
            FALLBACK_REST="${FALLBACK#*|}"
            FALLBACK_CUSTOM="${FALLBACK_REST%%|*}"
            FALLBACK_STEPS="${FALLBACK_REST##*|}"
            ui_print "! Сохранённый профиль $PROFILE_STEPS несовместим с текущей прошивкой"
            if [ "$FALLBACK_PROFILE" = "stock" ]; then
                ui_print "- Для безопасного обновления выбран штатный профиль"
            else
                ui_print "- Для безопасного обновления выбран подтверждённый профиль $FALLBACK_STEPS"
            fi
            PROFILE="$FALLBACK_PROFILE"
            CUSTOM="$FALLBACK_CUSTOM"
            ar_write_config "$PROFILE" "$CUSTOM" 1 "$FALLBACK_STEPS" "$(ar_cfg_get last_confirmed)" "reboot_required" "$(ar_cfg_get verification_failures)" "$(ar_cfg_get last_verified_build)"
            ;;
    esac
fi
ar_render_system_prop "$PROFILE" "$CUSTOM" || abort "! Не удалось сформировать system.prop"

ROOT_MANAGER="$(ar_root_manager)"
ar_rom_detect
ui_print "- ID: audiorange"
ui_print "- Автор: Lolokeksu"
ui_print "- Root-менеджер: $ROOT_MANAGER"
ui_print "- Система: $ANDROID_NAME / API $API_LEVEL"
ui_print "- Оболочка: $AR_ROM_NAME"
[ "$AR_ROM_VERSION" != "unknown" ] && ui_print "- Версия оболочки: $AR_ROM_VERSION"
ui_print "- Канал: Beta"
ui_print "- Кодовый диапазон: Android 13–16 / API 33–36"
ui_print "- Подтверждённое ядро функции: RMX3700 / Android 13 / APatch"
ui_print "- WebUI: APatch и KernelSU; Magisk — CLI/Action"
ui_print "- Неизвестные прошивки: адаптивная проверка после перезагрузки"
COMPAT_LIMIT="$(ar_compat_get known_max)"
COMPAT_SOURCE="$(ar_compat_get source)"
if ar_is_uint "$COMPAT_LIMIT"; then
    ui_print "- OEM-предел точной прошивки: $COMPAT_LIMIT"
    ui_print "- Источник совместимости: $(ar_compat_source_text "$COMPAT_SOURCE")"
else
    ui_print "- OEM-предел: неизвестен; профили проверяются после перезагрузки"
fi
case "$PROFILE" in
    stock) INSTALL_PROFILE="штатный" ;;
    custom) INSTALL_PROFILE="пользовательский: $CUSTOM шагов" ;;
    *) INSTALL_PROFILE="$PROFILE шагов" ;;
esac
ui_print "- Выбранный профиль: $INSTALL_PROFILE"
ui_print "- Интерфейс: WebUI для APatch и KernelSU"
ui_print "- Раннее применение свойства: post-fs-data / resetprop -n"
if ar_install_cli_wrapper; then
    ui_print "- Короткая команда: su -c audiorange"
else
    ui_print "- Короткая команда будет проверена после загрузки"
fi
ui_print "- Автообновление: GitHub update.json"
ui_print "- Для применения настроек перезагрузите Android"

ar_history "install version=v1.0.0-beta.1 root=$ROOT_MANAGER profile=$PROFILE custom=$CUSTOM author=Lolokeksu"

set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/audiorangectl" 0 0 0755
set_perm "$MODPATH/system/bin/audiorange" 0 0 0755
set_perm "$MODPATH/common/audiorange-lib.sh" 0 0 0644
set_perm "$MODPATH/system.prop" 0 0 0644
set_perm "$MODPATH/module.prop" 0 0 0644
set_perm "$MODPATH/manifest.sha256" 0 0 0644


ui_print "- Установка завершена без изменения системных разделов"
