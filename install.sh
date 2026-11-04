#!/bin/sh
# Установщик singbox-ui: подключает репозиторий, ставит панель и запускает
# singbox-ui, который настраивает всё остальное.
# singbox-ui installer: adds the repository, installs the panel and runs
# singbox-ui, which configures everything else.
#
#   CHANNEL=stable|beta|git|dev   канал репозитория (BRANCH=dev значит dev)
#                                 repository channel (BRANCH=dev means dev)
#   остальные переменные передаются в singbox-ui (см. singbox-ui --help)
#   other variables are passed on to singbox-ui

REPO_BASE="${REPO_BASE:-https://openwrt.mrvokintos.ru}"
GITHUB_REPO="mrvokintos/luci-app-singbox-ui"
ARTIFACTS_URL="https://raw.githubusercontent.com/$GITHUB_REPO/artifacts"
SETUP=/usr/sbin/singbox-ui
# Сборки до переименования ставили только singbox-ui-setup / Builds before the rename only had singbox-ui-setup
SETUP_OLD=/usr/sbin/singbox-ui-setup

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

# Ключ и фид панели. Фид с ядрами добавляет singbox-ui, если ядро
# выбрано из репозитория. Key and panel feed; singbox-ui adds the core
# feed when the core comes from the repository.
add_repo() {
    if [ "$PM" = apk ]; then
        mkdir -p /etc/apk/keys /etc/apk/repositories.d
        [ -s /etc/apk/keys/openwrt.rsa.pub ] || fetch "$REPO_BASE/keys/openwrt.rsa.pub" /etc/apk/keys/openwrt.rsa.pub || return 1
        list=/etc/apk/repositories.d/mrvoki.list
        grep -qF "$FEED/APKINDEX.tar.gz" "$list" 2>/dev/null && return 0
        {
            echo "# singbox-ui: managed by singbox-ui (channel: $CHANNEL)"
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
            echo "# singbox-ui: managed by singbox-ui (channel: $CHANNEL)"
            echo "src/gz mrvoki_all $FEED"
        } >> "$feeds.tmp"
        mv -f "$feeds.tmp" "$feeds"
    fi
}

# Только панель: без --upgrade, чтобы не обновлять заодно её зависимости
# (luci-base и т.п.). Panel only: no --upgrade, so its dependencies are not
# upgraded along the way.
install_from_repo() {
    if [ "$PM" = apk ]; then
        retry apk update >/dev/null || return 1
        if apk info -e luci-app-singbox-ui >/dev/null 2>&1; then
            apk upgrade luci-app-singbox-ui
        else
            apk add luci-app-singbox-ui
        fi
    else
        retry opkg update >/dev/null || return 1
        opkg install luci-app-singbox-ui
    fi
}

# URL пакета вне репозитория: dev/git — свежая сборка из артефактов CI,
# stable/beta — новый релиз на GitHub (если обычного нет, то пре-релиз).
# Package URL outside the repo: dev/git take the newest CI artifact,
# stable/beta the newest GitHub release (a pre-release if there is no release).
github_package_url() {
    local branch name list
    case "$CHANNEL" in
        dev|git)
            [ "$CHANNEL" = dev ] && branch=dev || branch=main
            list=$(fetch "$ARTIFACTS_URL/$branch/$EXT/index.txt" - 2>/dev/null) || return 1
            # luci-app-singbox-ui-<branch>-<sha>-<YYYYmmdd>-<HHMM>.<ext>: по дате / by date
            name=$(printf '%s\n' "$list" | grep -E '^[A-Za-z0-9._+-]+$' |
                awk -F- '{ print $(NF - 1) $NF "\t" $0 }' | sort | tail -n 1 | cut -f2)
            [ -n "$name" ] && echo "$ARTIFACTS_URL/$branch/$EXT/$name"
            ;;
        *)
            fetch "https://api.github.com/repos/$GITHUB_REPO/releases" - 2>/dev/null |
                grep -o "https://[^\"]*/luci-app-singbox-ui\.$EXT" | head -n 1
            ;;
    esac
}

install_from_github() {
    local file="/tmp/luci-app-singbox-ui.$EXT" url rc
    url=$(github_package_url)
    [ -n "$url" ] || return 1
    say "$url"
    fetch "$url" "$file" || { rm -f "$file"; return 1; }
    if [ "$PM" = apk ]; then
        apk add --allow-untrusted "$file"
    else
        opkg install "$file"
    fi
    rc=$?
    rm -f "$file"
    return "$rc"
}

trap cleanup EXIT

say "singbox-ui: $PM, channel $CHANNEL"
say "Repository / Репозиторий: $FEED"
if add_repo && install_from_repo; then
    :
else
    warn "Repository is not available, using GitHub / Репозиторий недоступен, ставлю с GitHub"
    install_from_github || fail "Cannot install luci-app-singbox-ui / Не удалось установить luci-app-singbox-ui"
fi

has_setup() {
    [ -x "$SETUP" ] || { [ -x "$SETUP_OLD" ] && SETUP="$SETUP_OLD"; }
}

if ! has_setup; then
    warn "Channel $CHANNEL has a panel without the setup command, trying GitHub"
    warn "В канале $CHANNEL панель без команды настройки, пробую GitHub"
    install_from_github
fi
has_setup || fail "This build has no setup command; try CHANNEL=dev / в этой сборке нет команды настройки, попробуйте CHANNEL=dev"

cleanup
trap - EXIT
exec "$SETUP" "$@"
