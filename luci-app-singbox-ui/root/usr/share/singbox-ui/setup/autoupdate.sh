#!/bin/sh
# Автообновление из репозитория через cron / Auto-update from the repo via cron.
# Режимы / modes: off | ui (панель / panel only) | all (панель и ядро / panel and core).
# Пути идут через $SBUI_ROOT (для тестов).

AUTOUPDATE_MARK="# singbox-ui-autoupdate"
AUTOUPDATE_JOB="/usr/libexec/singbox-ui-autoupdate"

_au_crontab() { printf '%s' "$SBUI_ROOT/etc/crontabs/root"; }

autoupdate_mode_valid() {
    case "$1" in off|ui|all) return 0 ;; esac
    return 1
}

# Текущий режим по crontab / Current mode from crontab
autoupdate_current() {
    local file mode
    file=$(_au_crontab)
    mode=""
    [ -f "$file" ] && mode=$(grep -F "$AUTOUPDATE_MARK" "$file" | sed -n "s#.*$AUTOUPDATE_JOB \([a-z]*\).*#\1#p" | head -n 1)
    autoupdate_mode_valid "$mode" || mode=off
    printf '%s\n' "$mode"
}

# Случайное время ночью, чтобы роутеры не ходили в репозиторий одновременно
# A random night time so routers do not hit the repo at the same moment
_au_schedule() {
    awk 'BEGIN { srand(); printf "%d %d * * *\n", int(rand() * 60), 3 + int(rand() * 3) }'
}

# autoupdate_set MODE
autoupdate_set() {
    local mode="$1" file tmp schedule
    autoupdate_mode_valid "$mode" || return 1
    file=$(_au_crontab)
    if [ -n "${SETUP_DRY_RUN:-}" ]; then
        echo "[dry-run] autoupdate $mode -> $file"
        return 0
    fi
    # Сохранить время, если задача уже есть / Keep the schedule if the job exists
    schedule=""
    [ -f "$file" ] && schedule=$(grep -F "$AUTOUPDATE_MARK" "$file" | awk '{ print $1, $2, $3, $4, $5; exit }')
    [ -n "$schedule" ] || schedule=$(_au_schedule)

    mkdir -p "${file%/*}" || return 1
    tmp="$file.tmp.$$"
    {
        [ -f "$file" ] && grep -vF "$AUTOUPDATE_MARK" "$file"
        [ "$mode" = off ] || printf '%s %s %s %s\n' "$schedule" "$AUTOUPDATE_JOB" "$mode" "$AUTOUPDATE_MARK"
    } > "$tmp"
    mv -f "$tmp" "$file" || return 1

    [ -z "$SBUI_ROOT" ] || return 0
    if [ "$mode" != off ]; then
        /etc/init.d/cron enable >/dev/null 2>&1
    fi
    /etc/init.d/cron restart >/dev/null 2>&1 || true
}
