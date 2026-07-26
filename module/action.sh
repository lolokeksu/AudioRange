#!/system/bin/sh

MODDIR=${0%/*}
CTL="$MODDIR/bin/audiorangectl"

printf '%s\n' \
  "AudioRange v1.0.0-beta.1 Beta · Lolokeksu" \
  "Action работает только в режиме чтения." \
  "Профиль и системные настройки не изменяются." \
  ""

if [ ! -x "$CTL" ]; then
    printf '%s\n' "Ошибка: контроллер модуля недоступен: $CTL" >&2
    exit 1
fi

printf '%s\n' "===== ТЕКУЩЕЕ СОСТОЯНИЕ =====" ""
"$CTL" status
status_rc=$?

printf '%s\n' "" "===== ДИАГНОСТИКА =====" ""
"$CTL" doctor
doctor_rc=$?

printf '%s\n' "" "Action завершён без изменения профиля."

[ "$status_rc" -eq 0 ] && [ "$doctor_rc" -eq 0 ]
