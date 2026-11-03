#!/bin/sh
# Установщик singbox-ui: подключает репозиторий, ставит панель и запускает
# singbox-ui-setup, который настраивает всё остальное.
# singbox-ui installer: adds the repository, installs the panel and runs
# singbox-ui-setup, which configures everything else.
#
#   CHANNEL=stable|beta|git|dev   канал репозитория (BRANCH=dev значит dev)
#                                 repository channel (BRANCH=dev means dev)
#   остальные переменные передаются в singbox-ui-setup (см. singbox-ui-setup --help)
#   other variables are passed on to singbox-ui-setup

REPO_BASE="${REPO_BASE:-https://openwrt.mrvokintos.ru}"
GITHUB_LATEST="https://github.com/mrvokintos/luci-app-singbox-ui/releases/latest/download"
SETUP=/usr/sbin/singbox-ui-setup

say() { printf '  \033[38;5;85m▸\033[0m %s\n' "$*"; }
warn() { printf '  \033[38;5;214m!\033[0m %s\n' "$*"; }
fail() { printf '  \033[38;5;203m✗ %s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
    # Скрипт удаляет себя, как и раньше / The script removes itself, as before
    [ -n "${SBUI_KEEP_SCRIPT:-}" ] || case "$0" in /root/install.sh|/tmp/install.sh) rm -f -- "$0" ;; esac
}

[ "$(id -u)" = 0 ] || fail "Run as root / Запустите от root"

if [ -z "${CHANNEL:-}" ]; then
    case "${BRANCH:-main}" in dev) CHANNEL=dev ;; *) CHANNEL=stable ;; esac
fi
case "$CHANNEL" in stable|beta|git|dev) ;; *) fail "CHANNEL: stable | beta | git | dev" ;; esac
export CHANNEL

if command -v apk >/dev/null 2>&1; then
    PM=apk EXT=apk
elif command -v opkg >/dev/null 2>&1; then
    PM=opkg EXT=ipk
else
    fail "No apk/opkg / Нет apk/opkg"
fi

fetch() {
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        curl -fsSL -o "$2" "$1"
    fi
}

retry() {
    local i=1
    while [ "$i" -le 3 ]; do
        "$@" && return 0
        sleep $((i * 5))
        i=$((i + 1))
    done
    return 1
}

if [ "$CHANNEL" = stable ]; then FEED="$REPO_BASE/packages/all"; else FEED="$REPO_BASE/packages/$CHANNEL/all"; fi

# Ключ и фид панели. Фид с ядрами добавляет singbox-ui-setup, если ядро
# выбрано из репозитория. Key and panel feed; singbox-ui-setup adds the core
# feed when the core comes from the repository.
add_repo() {
    if [ "$PM" = apk ]; then
        mkdir -p /etc/apk/keys /etc/apk/repositories.d
        [ -s /etc/apk/keys/openwrt.rsa.pub ] || fetch "$REPO_BASE/keys/openwrt.rsa.pub" /etc/apk/keys/openwrt.rsa.pub || return 1
        list=/etc/apk/repositories.d/mrvoki.list
        grep -qF "$FEED/APKINDEX.tar.gz" "$list" 2>/dev/null && return 0
        {
            echo "# singbox-ui: managed by singbox-ui-setup (channel: $CHANNEL)"
            echo "$FEED/APKINDEX.tar.gz"
        } > "$list"
    else
        mkdir -p /etc/opkg/keys
        [ -s /etc/opkg/keys/5bab0ffe1aafaf8f ] || fetch "$REPO_BASE/keys/5bab0ffe1aafaf8f" /etc/opkg/keys/5bab0ffe1aafaf8f || return 1
        feeds=/etc/opkg/customfeeds.conf
        grep -q "^src/gz mrvoki_all $FEED\$" "$feeds" 2>/dev/null && return 0
        touch "$feeds"
        awk '$1 ~ /^src/ && $2 ~ /^mrvoki_/ { next } /^# singbox-ui:/ { next } { print }' "$feeds" > "$feeds.tmp"
        {
            echo "# singbox-ui: managed by singbox-ui-setup (channel: $CHANNEL)"
            echo "src/gz mrvoki_all $FEED"
        } >> "$feeds.tmp"
        mv -f "$feeds.tmp" "$feeds"
    fi
}

install_from_repo() {
    if [ "$PM" = apk ]; then
        retry apk update >/dev/null && apk add --upgrade luci-app-singbox-ui
    else
        retry opkg update >/dev/null && opkg install luci-app-singbox-ui
    fi
}

install_from_github() {
    local file="/tmp/luci-app-singbox-ui.$EXT"
    fetch "$GITHUB_LATEST/luci-app-singbox-ui.$EXT" "$file" || return 1
    if [ "$PM" = apk ]; then
        apk add --allow-untrusted "$file"
    else
        opkg install "$file"
    fi
    local rc=$?
    rm -f "$file"
    return "$rc"
}

trap cleanup EXIT

say "singbox-ui: $PM, channel $CHANNEL"
say "Repository / Репозиторий: $FEED"
if add_repo && install_from_repo; then
    :
else
    warn "Repository is not available, using the GitHub release / Репозиторий недоступен, ставлю релиз с GitHub"
    install_from_github || fail "Cannot install luci-app-singbox-ui / Не удалось установить luci-app-singbox-ui"
fi

if [ ! -x "$SETUP" ]; then
    warn "Channel $CHANNEL has a panel without singbox-ui-setup, trying the GitHub release"
    warn "В канале $CHANNEL панель без singbox-ui-setup, пробую релиз с GitHub"
    install_from_github
fi
[ -x "$SETUP" ] || fail "singbox-ui-setup is missing in this build; try CHANNEL=dev / в этой сборке нет singbox-ui-setup, попробуйте CHANNEL=dev"

cleanup
trap - EXIT
exec "$SETUP" "$@"
