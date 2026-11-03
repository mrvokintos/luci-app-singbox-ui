#!/bin/sh
# Модули singbox-ui-setup на фейковом корне / singbox-ui-setup modules on a fake root.
# Запуск / run: sh tests/setup.test.sh (работает и в busybox ash на роутере)
set -eu

lib="${SETUP_LIB:-luci-app-singbox-ui/root/usr/share/singbox-ui/setup}"
SBUI_ROOT="$(mktemp -d)"
export SBUI_ROOT
trap 'rm -rf "$SBUI_ROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
check() { "$@" || fail "$*"; }

# Без сети: ключ "скачивается" из локального файла / No network: the key is a local file
_repo_fetch() { printf 'key\n' > "$2"; }

. "$lib/ui.sh"
. "$lib/pkg.sh"
. "$lib/repo.sh"
_repo_fetch() { printf 'key\n' > "$2"; }
. "$lib/autoupdate.sh"
. "$lib/core.sh"

# ── repo_feed_urls ──────────────────────────────────────────────────────────
out=$(repo_feed_urls stable aarch64_cortex-a53 1)
check [ "$out" = "mrvoki_all https://openwrt.mrvokintos.ru/packages/all
mrvoki_core https://openwrt.mrvokintos.ru/packages/aarch64_cortex-a53" ]
out=$(repo_feed_urls dev aarch64_cortex-a53 0)
check [ "$out" = "mrvoki_all https://openwrt.mrvokintos.ru/packages/dev/all" ]
out=$(repo_feed_urls beta mipsel_24kc 1)
check [ "$out" = "mrvoki_all https://openwrt.mrvokintos.ru/packages/beta/all" ]
check repo_channel_valid git
if repo_channel_valid main; then fail "main is not a channel"; fi

# ── apk ─────────────────────────────────────────────────────────────────────
PKG_IS_APK=1
list="$SBUI_ROOT/etc/apk/repositories.d/mrvoki.list"
check [ -z "$(repo_current_channel)" ]
repo_enable dev aarch64_cortex-a53 0
check [ -s "$SBUI_ROOT/etc/apk/keys/openwrt.rsa.pub" ]
check grep -qx 'https://openwrt.mrvokintos.ru/packages/dev/all/APKINDEX.tar.gz' "$list"
check [ "$(repo_current_channel)" = dev ]
if repo_has_core_feed; then fail "apk: core feed must be absent"; fi

repo_enable stable aarch64_cortex-a53 1
check [ "$(repo_current_channel)" = stable ]
check repo_has_core_feed
check [ "$(grep -vc '^#' "$list")" = 2 ]
check grep -qx 'https://openwrt.mrvokintos.ru/packages/aarch64_cortex-a53/APKINDEX.tar.gz' "$list"
repo_enable stable aarch64_cortex-a53 1
check [ "$(grep -vc '^#' "$list")" = 2 ]
repo_disable
check [ ! -e "$list" ]
check [ -z "$(repo_current_channel)" ]

# ── opkg ────────────────────────────────────────────────────────────────────
PKG_IS_APK=0
feeds="$SBUI_ROOT/etc/opkg/customfeeds.conf"
mkdir -p "${feeds%/*}"
printf '%s\n' '# my feeds' 'src/gz other https://example.com/packages' 'src/gz mrvoki_repo https://openwrt.mrvokintos.ru/packages/aarch64_cortex-a53' > "$feeds"
repo_enable git aarch64_cortex-a53 1
check [ -s "$SBUI_ROOT/etc/opkg/keys/5bab0ffe1aafaf8f" ]
check grep -qx 'src/gz other https://example.com/packages' "$feeds"
check grep -qx '# my feeds' "$feeds"
check grep -qx 'src/gz mrvoki_all https://openwrt.mrvokintos.ru/packages/git/all' "$feeds"
check grep -qx 'src/gz mrvoki_core https://openwrt.mrvokintos.ru/packages/git/aarch64_cortex-a53' "$feeds"
if grep -q mrvoki_repo "$feeds"; then fail "opkg: legacy feed line must be replaced"; fi
check [ "$(repo_current_channel)" = git ]
check repo_has_core_feed
repo_enable beta aarch64_cortex-a53 0
check [ "$(grep -c mrvoki_ "$feeds")" = 1 ]
check [ "$(grep -c '^# singbox-ui:' "$feeds")" = 1 ]
check [ "$(repo_current_channel)" = beta ]
if repo_has_core_feed; then fail "opkg: core feed must be gone"; fi
repo_disable
check [ "$(grep -c mrvoki_ "$feeds" || true)" = 0 ]
check grep -qx 'src/gz other https://example.com/packages' "$feeds"

# ── autoupdate ──────────────────────────────────────────────────────────────
tab="$SBUI_ROOT/etc/crontabs/root"
check [ "$(autoupdate_current)" = off ]
mkdir -p "${tab%/*}"
echo '0 1 * * * /bin/true # mine' > "$tab"
autoupdate_set ui
check [ "$(autoupdate_current)" = ui ]
check grep -qx '0 1 \* \* \* /bin/true # mine' "$tab"
check [ "$(grep -c singbox-ui-autoupdate "$tab")" = 1 ]
schedule=$(grep singbox-ui-autoupdate "$tab" | awk '{ print $1, $2 }')
autoupdate_set all
check [ "$(autoupdate_current)" = all ]
check [ "$(grep -c singbox-ui-autoupdate "$tab")" = 1 ]
check [ "$(grep singbox-ui-autoupdate "$tab" | awk '{ print $1, $2 }')" = "$schedule" ]
autoupdate_set off
check [ "$(autoupdate_current)" = off ]
check [ "$(grep -c singbox-ui-autoupdate "$tab" || true)" = 0 ]
check grep -qx '0 1 \* \* \* /bin/true # mine' "$tab"
if autoupdate_set weekly 2>/dev/null; then fail "autoupdate accepted an unknown mode"; fi

# ── core_installed_kind ─────────────────────────────────────────────────────
installed=""
pkg_is_installed() { [ "$1" = "$installed" ]; }
src="$SBUI_ROOT/etc/singbox-ui/core-source"
mkdir -p "${src%/*}"
check [ -z "$(core_installed_kind)" ]
installed=sing-box; rm -f "$src"
check [ "$(core_installed_kind)" = feed ]
echo SagerNet/sing-box > "$src"
check [ "$(core_installed_kind)" = original ]
echo repo > "$src"
check [ "$(core_installed_kind)" = clean ]
installed=sing-box-extended
check [ "$(core_installed_kind)" = clean-extended ]
echo shtorm-7/sing-box-extended > "$src"
check [ "$(core_installed_kind)" = extended ]
check core_kind_uses_repo clean aarch64_cortex-a53
if core_kind_uses_repo clean mipsel_24kc; then fail "clean on mipsel must come from GitHub"; fi
if core_kind_uses_repo original aarch64_cortex-a53; then fail "original never uses the repo"; fi

echo "setup tests: ok"
