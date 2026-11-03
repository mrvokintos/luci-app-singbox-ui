#!/bin/sh
# Системные шаги: сервис, TUN, IPv6, сеть, резервные копии конфигов.
# System steps: service, TUN, IPv6, network check, config backups.
# Требует ui.sh и i18n.sh. В SETUP_DRY_RUN команды печатаются, а не выполняются.

MODE_SWITCH="${MODE_SWITCH:-/usr/libexec/singbox-ui-mode-switch}"
CONFIG_BACKUP_DIR="/tmp/singbox-ui-setup-backup"

# run CMD... — выполнить или напечатать в dry-run / run or print in dry-run
run() {
    if [ -n "${SETUP_DRY_RUN:-}" ]; then
        echo "[dry-run] $*"
        return 0
    fi
    "$@"
}

service_configure() {
    show_progress "$MSG_SERVICE_CONFIG"
    run uci set sing-box.main.enabled=1
    run uci set sing-box.main.user=root
    run uci commit sing-box
}

# Пустой или отсутствующий config.json / Missing or empty config.json
config_is_empty() {
    local f="$SBUI_ROOT/etc/sing-box/config.json"
    [ -s "$f" ] || return 0
    [ "$(tr -d ' \t\r\n' < "$f")" = "{}" ]
}

config_ensure() {
    [ -s "$SBUI_ROOT/etc/sing-box/config.json" ] && return 0
    run mkdir -p /etc/sing-box
    [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] write {} to /etc/sing-box/config.json"; return 0; }
    printf '{}\n' > /etc/sing-box/config.json
}

config_edit() {
    local editor="${EDITOR:-}"
    [ -n "$editor" ] || { command -v nano >/dev/null 2>&1 && editor=nano || editor=vi; }
    config_ensure
    run "$editor" /etc/sing-box/config.json
}

service_start() {
    show_progress "$MSG_SERVICE_START"
    run service sing-box enable
    run service sing-box restart
}

service_stop() {
    run service sing-box stop 2>/dev/null
    run service sing-box disable 2>/dev/null
    return 0
}

# Настроен ли TUN-интерфейс proxy / Whether the TUN proxy interface is configured
tun_configured() {
    [ "$(uci -q get network.proxy.device 2>/dev/null)" = singtun0 ]
}

tun_enable() {
    tun_configured && return 0
    show_progress "$MSG_TUN_ENABLE"
    run "$MODE_SWITCH" enable-tun
}

tun_disable() {
    tun_configured || return 0
    show_progress "$MSG_TUN_DISABLE"
    run "$MODE_SWITCH" disable-tun
}

# Остатки TPROXY от старых версий / TPROXY leftovers from older versions
tproxy_cleanup() {
    [ -f "$SBUI_ROOT/etc/sing-box/tproxy.nft" ] || uci -q get firewall.singbox_tproxy >/dev/null 2>&1 || return 0
    show_progress "$MSG_TPROXY_CLEANUP"
    run "$MODE_SWITCH" disable-tproxy
}

ipv6_disabled() {
    [ "$(uci -q get network.lan.ipv6 2>/dev/null)" = 0 ]
}

ipv6_disable() {
    ipv6_disabled && return 0
    show_progress "$MSG_IPV6_DISABLING"
    run uci set network.lan.ipv6=0
    run uci set network.wan.ipv6=0
    run uci set dhcp.lan.dhcpv6=disabled
    run /etc/init.d/odhcpd disable
    run uci commit
}

ipv6_restore() {
    ipv6_disabled || return 0
    show_progress "$MSG_IPV6_RESTORING"
    run uci set network.lan.ipv6=1
    run uci set network.wan.ipv6=1
    run uci set dhcp.lan.dhcpv6=server
    run /etc/init.d/odhcpd enable
    run uci commit
}

# Проверка доступности сети / Network availability check
network_check() {
    local timeout="${NETWORK_TIMEOUT:-300}" interval=5 elapsed=0 target
    local targets="77.88.8.8 1.1.1.1 8.8.8.8 9.9.9.9 223.5.5.5 94.140.14.14"
    [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] network check"; return 0; }
    show_progress "$MSG_NETWORK_CHECK"
    while [ "$elapsed" -lt "$timeout" ]; do
        for target in $targets; do
            if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
                show_success "$(printf "$MSG_NETWORK_OK" "$target" "$elapsed")"
                return 0
            fi
        done
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    show_error "$(printf "$MSG_NETWORK_FAIL" "$timeout")"
    return 1
}

# Копия /etc/sing-box/*.json перед заменой ядра: удаление пакета может
# забрать config.json (это conffile пакета sing-box).
# Back up configs before a core change: removing the package may take
# config.json with it (it is a conffile of the sing-box package).
configs_backup() {
    [ -n "${SETUP_DRY_RUN:-}" ] && return 0
    rm -rf "$CONFIG_BACKUP_DIR"
    mkdir -p "$CONFIG_BACKUP_DIR"
    for f in /etc/sing-box/*.json; do
        [ -f "$f" ] && cp -p "$f" "$CONFIG_BACKUP_DIR/"
    done
    return 0
}

# Вернуть пропавшие или сброшенные файлы / Restore missing or reset files
configs_restore() {
    [ -n "${SETUP_DRY_RUN:-}" ] && return 0
    [ -d "$CONFIG_BACKUP_DIR" ] || return 0
    mkdir -p /etc/sing-box
    for f in "$CONFIG_BACKUP_DIR"/*.json; do
        [ -f "$f" ] || continue
        cmp -s "$f" "/etc/sing-box/${f##*/}" || cp -p "$f" /etc/sing-box/
    done
    rm -rf "$CONFIG_BACKUP_DIR"
}

# Сохранить выбор в uci / Store choices in uci
setup_save() {
    [ -n "${SETUP_DRY_RUN:-}" ] && { echo "[dry-run] save singbox-ui.setup"; return 0; }
    [ -f /etc/config/singbox-ui ] || : > /etc/config/singbox-ui
    uci -q get singbox-ui.setup >/dev/null || uci set singbox-ui.setup=setup
    uci set singbox-ui.setup.lang="$S_LANG"
    uci set singbox-ui.setup.channel="$S_CHANNEL"
    uci set singbox-ui.setup.autoupdate="$S_AUTOUPDATE"
    uci set singbox-ui.setup.ipv6="$S_IPV6"
    uci commit singbox-ui
}
