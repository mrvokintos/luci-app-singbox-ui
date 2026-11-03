#!/bin/sh
# Репозиторий openwrt.mrvokintos.ru: ключи и фиды для apk/opkg.
# Package repository openwrt.mrvokintos.ru: keys and feeds for apk/opkg.
#
# Каналы / channels: stable (packages/...), beta, git, dev (packages/<channel>/...).
# Фид "all" содержит только панель. Фид архитектуры содержит ещё sing-box и
# sing-box-extended, поэтому подключается только если ядро ставится из репозитория:
# иначе любой apk upgrade тихо заменит ядро из официального фида.
# The "all" feed has the panel only. The arch feed also carries sing-box and
# sing-box-extended, so it is added only when the core comes from this repo:
# otherwise any apk upgrade would silently replace the core.
#
# Требует pkg.sh (PKG_IS_APK). Пути идут через $SBUI_ROOT (для тестов).

: "${REPO_BASE:=https://openwrt.mrvokintos.ru}"
# Архитектуры, для которых в репозитории есть ядра / Arches with cores in the repo
: "${REPO_CORE_ARCHES:=aarch64_cortex-a53}"

REPO_APK_KEY_NAME="openwrt.rsa.pub"
REPO_OPKG_KEY_NAME="5bab0ffe1aafaf8f"

_repo_apk_list() { printf '%s' "$SBUI_ROOT/etc/apk/repositories.d/mrvoki.list"; }
_repo_apk_key() { printf '%s' "$SBUI_ROOT/etc/apk/keys/$REPO_APK_KEY_NAME"; }
_repo_opkg_feeds() { printf '%s' "$SBUI_ROOT/etc/opkg/customfeeds.conf"; }
_repo_opkg_key() { printf '%s' "$SBUI_ROOT/etc/opkg/keys/$REPO_OPKG_KEY_NAME"; }

repo_channel_valid() {
    case "$1" in stable|beta|git|dev) return 0 ;; esac
    return 1
}

repo_arch_has_core() {
    case " $REPO_CORE_ARCHES " in *" $1 "*) return 0 ;; esac
    return 1
}

# repo_channel_url CHANNEL -> base URL of the channel
repo_channel_url() {
    if [ "$1" = stable ]; then
        printf '%s/packages\n' "$REPO_BASE"
    else
        printf '%s/packages/%s\n' "$REPO_BASE" "$1"
    fi
}

# repo_feed_urls CHANNEL ARCH WITH_CORE -> "name url" per line
# WITH_CORE=1 adds the arch feed (only for arches that have cores).
repo_feed_urls() {
    local base
    base=$(repo_channel_url "$1")
    printf 'mrvoki_all %s/all\n' "$base"
    if [ "${3:-0}" = 1 ] && repo_arch_has_core "$2"; then
        printf 'mrvoki_core %s/%s\n' "$base" "$2"
    fi
}

_repo_fetch() {
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        curl -fsSL -o "$2" "$1"
    fi
}

# Скачать ключ, если его нет / Fetch the signing key if missing
repo_install_key() {
    local key url
    if [ "$PKG_IS_APK" -eq 1 ]; then
        key=$(_repo_apk_key)
        url="$REPO_BASE/keys/$REPO_APK_KEY_NAME"
    else
        key=$(_repo_opkg_key)
        url="$REPO_BASE/keys/$REPO_OPKG_KEY_NAME"
    fi
    [ -s "$key" ] && return 0
    [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] fetch $url -> $key"; return 0; }
    mkdir -p "${key%/*}" || return 1
    _repo_fetch "$url" "$key.tmp" && [ -s "$key.tmp" ] && mv -f "$key.tmp" "$key" || {
        rm -f "$key.tmp"
        return 1
    }
}

# repo_write_feeds CHANNEL ARCH WITH_CORE — заменить свои строки фидов
# Replace our feed lines; foreign lines are kept.
repo_write_feeds() {
    local channel="$1" arch="$2" with_core="${3:-0}" file tmp
    repo_channel_valid "$channel" || return 1
    if [ "$PKG_IS_APK" -eq 1 ]; then
        # Файл целиком наш. apk 3 нужен полный путь к APKINDEX.tar.gz: без него
        # он ищет индекс в <url>/<arch>/APKINDEX.tar.gz (раскладка Alpine).
        # The file is ours. apk 3 needs the full APKINDEX.tar.gz path, otherwise
        # it looks for <url>/<arch>/APKINDEX.tar.gz (Alpine layout).
        file=$(_repo_apk_list)
        [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] write $file ($channel)"; return 0; }
        mkdir -p "${file%/*}" || return 1
        tmp="$file.tmp.$$"
        {
            echo "# singbox-ui: managed by singbox-ui-setup (channel: $channel)"
            repo_feed_urls "$channel" "$arch" "$with_core" | while read -r _name url; do
                echo "$url/APKINDEX.tar.gz"
            done
        } > "$tmp" && mv -f "$tmp" "$file"
    else
        file=$(_repo_opkg_feeds)
        [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] write $file ($channel)"; return 0; }
        mkdir -p "${file%/*}" || return 1
        tmp="$file.tmp.$$"
        {
            [ -f "$file" ] && awk '
                $1 ~ /^src/ && $2 ~ /^mrvoki_/ { next }
                /^# singbox-ui:/ { next }
                { print }' "$file"
            echo "# singbox-ui: managed by singbox-ui-setup (channel: $channel)"
            repo_feed_urls "$channel" "$arch" "$with_core" | while read -r name url; do
                echo "src/gz $name $url"
            done
        } > "$tmp" && mv -f "$tmp" "$file"
    fi
}

# repo_enable CHANNEL ARCH WITH_CORE
repo_enable() {
    repo_install_key && repo_write_feeds "$@"
}

repo_disable() {
    local file tmp
    if [ "$PKG_IS_APK" -eq 1 ]; then
        file=$(_repo_apk_list)
        [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] rm $file"; return 0; }
        rm -f "$file"
    else
        file=$(_repo_opkg_feeds)
        [ -f "$file" ] || return 0
        [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] clean $file"; return 0; }
        tmp="$file.tmp.$$"
        awk '
            $1 ~ /^src/ && $2 ~ /^mrvoki_/ { next }
            /^# singbox-ui:/ { next }
            { print }' "$file" > "$tmp" && mv -f "$tmp" "$file"
    fi
}

# Текущий канал по записанным фидам, пусто если репозиторий не подключён
# Current channel from the feeds, empty when the repo is not configured
repo_current_channel() {
    local file line
    if [ "$PKG_IS_APK" -eq 1 ]; then file=$(_repo_apk_list); else file=$(_repo_opkg_feeds); fi
    [ -f "$file" ] || return 0
    line=$(grep -o "$REPO_BASE/packages[^ ]*/all" "$file" | head -n 1)
    [ -n "$line" ] || return 0
    line=${line#"$REPO_BASE/packages"}
    line=${line%/all}
    line=${line#/}
    printf '%s\n' "${line:-stable}"
}

# Подключён ли фид с ядрами / Whether the core feed is configured
repo_has_core_feed() {
    local file
    if [ "$PKG_IS_APK" -eq 1 ]; then file=$(_repo_apk_list); else file=$(_repo_opkg_feeds); fi
    [ -f "$file" ] || return 1
    grep -v '^#' "$file" | grep -F "$REPO_BASE/packages" |
        grep -v '/all\(/APKINDEX\.tar\.gz\)\{0,1\}$' | grep -q .
}
