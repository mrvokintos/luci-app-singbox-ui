#!/bin/sh
# Устаревший скрипт: установка теперь идёт через install.sh и singbox-ui.
# Скрипт оставлен для старых ссылок и передаёт все переменные дальше.
# Deprecated: installation now goes through install.sh and singbox-ui.
# Kept for old links; all variables are passed on.
BRANCH="${BRANCH:-main}"
url="https://raw.githubusercontent.com/${SBUI_GITHUB_REPO:-mrvokintos/luci-app-singbox-ui}/$BRANCH/install.sh"
echo "  ▸ $(basename "$0") -> install.sh ($BRANCH)"
wget -O /root/install.sh "$url" || exit 1
chmod 0755 /root/install.sh
case "$0" in /root/*) rm -f -- "$0" ;; esac
BRANCH="$BRANCH" exec sh /root/install.sh "$@"
