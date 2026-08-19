#!/bin/sh
BRANCH="${BRANCH:-main}"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
UI_PATH="$SCRIPT_DIR/lib/ui.sh"
PKG_PATH="$SCRIPT_DIR/lib/pkg.sh"
MS_PATH="$SCRIPT_DIR/lib/singbox-ui-mode-switch"
UI_DOWNLOADED=0
PKG_DOWNLOADED=0
MS_DOWNLOADED=0
cleanup_lib() {
    if [ "${UI_DOWNLOADED:-0}" -eq 1 ] || [ "${PKG_DOWNLOADED:-0}" -eq 1 ] || [ "${MS_DOWNLOADED:-0}" -eq 1 ]; then
        local cleanup_msg="${MSG_CLEANUP_LIB:-Cleaning library...}"
        if command -v show_progress >/dev/null 2>&1; then
            show_progress "$cleanup_msg"
        else
            echo "$cleanup_msg"
        fi
        rm -f -- "$UI_PATH" "$PKG_PATH" "$MS_PATH"
        rmdir -- "$SCRIPT_DIR/lib" 2>/dev/null || true
    fi
}
ensure_ui_library() {
    if [ -f "$UI_PATH" ]; then
        . "$UI_PATH"
        return 0
    fi

    mkdir -p "$SCRIPT_DIR/lib" 2>/dev/null
    ui_url="https://raw.githubusercontent.com/mrvokintos/luci-app-singbox-ui/$BRANCH/other/scripts/lib/ui.sh"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$UI_PATH" "$ui_url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$UI_PATH" "$ui_url" || return 1
    else
        echo "Missing UI library and downloader (wget/curl)" >&2
        return 1
    fi

    UI_DOWNLOADED=1
    . "$UI_PATH"
}
ensure_pkg_library() {
    if [ -f "$PKG_PATH" ]; then
        . "$PKG_PATH"
        detect_pkg_manager || return 1
        return 0
    fi

    mkdir -p "$SCRIPT_DIR/lib" 2>/dev/null
    pkg_url="https://raw.githubusercontent.com/mrvokintos/luci-app-singbox-ui/$BRANCH/other/scripts/lib/pkg.sh"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$PKG_PATH" "$pkg_url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$PKG_PATH" "$pkg_url" || return 1
    else
        echo "Missing pkg library and downloader (wget/curl)" >&2
        return 1
    fi

    PKG_DOWNLOADED=1
    . "$PKG_PATH"
    detect_pkg_manager || return 1
}

ensure_mode_switch() {
    mkdir -p "$SCRIPT_DIR/lib" 2>/dev/null
    local ms_url="https://raw.githubusercontent.com/mrvokintos/luci-app-singbox-ui/$BRANCH/other/scripts/lib/singbox-ui-mode-switch"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$MS_PATH" "$ms_url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$MS_PATH" "$ms_url" || return 1
    else
        echo "Missing mode-switch and downloader (wget/curl)" >&2
        return 1
    fi
    chmod +x "$MS_PATH"
    MODE_SWITCH="$MS_PATH"
    MS_DOWNLOADED=1
}

ensure_ui_library || {
    echo "Missing UI library: $UI_PATH" >&2
    exit 1
}
ensure_pkg_library || {
    echo "Missing pkg library: $PKG_PATH" >&2
    exit 1
}
ensure_mode_switch || {
    echo "Missing mode-switch: $MS_PATH" >&2
    exit 1
}
trap cleanup_lib EXIT HUP INT TERM

# Инициализация языка / Language initialization
init_language() {
    local script_name="install-singbox.sh"

    if [ -z "$LANG" ]; then
        while true; do
            show_message "Выберите язык / Select language [1/2]:"
            show_message "1. Русский (Russian)"
            show_message "2. English (Английский)"
            read_input " Ваш выбор / Your choice [1/2]: " LANG
            case "$LANG" in
                1|2)
                    break
                    ;;
                *)
                    show_error "Неверный выбор / Invalid choice"
                    ;;
            esac
        done
    fi

    case ${LANG:-2} in
        1)
            MSG_INSTALL_TITLE="Запуск! ($script_name)"
            MSG_UPDATE_PKGS="Обновление репозиториев..."
            MSG_PKGS_SUCCESS="Репозитории успешно обновлены"
            MSG_PKGS_ERROR="Ошибка обновления репозиториев"
            MSG_INSTALL_SINGBOX="Установка последней версии sing-box..."
            MSG_INSTALL_SINGBOX_SUCCESS="Установка sing-box завершена"
            MSG_INSTALL_SINGBOX_ERROR="Ошибка установки sing-box"
            MSG_UNINSTALL_SINGBOX="Удаление sing-box..."
            MSG_UNINSTALL_SINGBOX_SUCCESS="Удаление sing-box завершено"
            MSG_UNINSTALL_SINGBOX_ERROR="Ошибка удаления sing-box"
            MSG_SERVICE_CONFIG="Настройка системного сервиса..."
            MSG_SERVICE_APPLIED="Конфигурация сервиса применена"
            MSG_SERVICE_DISABLED="Сервис временно отключен"
            MSG_CONFIG_RESET="Конфигурационный файл сохранён"
            MSG_CLEANUP_LIB="Очистка библиотек..."
            MSG_CLEANUP="Очистка файлов..."
            MSG_CLEANUP_DONE="Файлы удалены!"
            MSG_COMPLETE="Выполнено! ($script_name)"
            MSG_DISABLE_IPV6="Отключение IPv6..."
            MSG_IPV6_DISABLED="IPv6 отключен"
            MSG_START_SERVICE="Запуск сервиса sing-box"
            MSG_SERVICE_STARTED="Сервис успешно запущен"
            MSG_OPERATION="Выберите тип операции:"
            MSG_INSTALL="1. Установка"
            MSG_DELETE="2. Удаление"
            MSG_REINSTALL_UPDATE="3. Переустановка/Обновление"
            MSG_CHOICE=" Ваш выбор: "
            MSG_ALREADY_INSTALLED="Ошибка: Пакет уже установлен. Для переустановки выберите опцию 3"
            MSG_INSTALLING="Установка..."
            MSG_INSTALL_SUCCESS="Установка завершена"
            MSG_UNINSTALLING="Полное удаление..."
            MSG_UNINSTALL_SUCCESS="Удаление завершено"
            MSG_NOT_INSTALLED="Ошибка: Пакет не установлен. Нечего удалять."
            MSG_INVALID_OPERATION="Ошибка: Некорректная операция"
            MSG_RESTORING_IPV6="Восстановление настроек IPv6..."
            MSG_IPV6_RESTORED="Настройки IPv6 восстановлены"
            MSG_REMOVING_CONFIGS="Удаление конфигурационных файлов..."
            MSG_NETWORK_CHECK="Проверка доступности сети..."
            MSG_NETWORK_SUCCESS="Сеть доступна (через %s, за %s сек)"
            MSG_NETWORK_ERROR="Сеть не доступна после %s сек!"
            MSG_MODE="Выберите режим установки:"
            MSG_TUN="1. TUN"
            MSG_TPROXY="2. TPROXY"
            MSG_MODE_CHOICE="Ваш выбор: "
            MSG_INSTALLING_TPROXY_MODE="Установка TPROXY режима..."
            MSG_UNINSTALLING_TPROXY_MODE="Удаление TPROXY режима..."
            MSG_TPROXY_NFT_INSTALL="Установка nftables (nft) для TPROXY..."
            MSG_TPROXY_NFT_INSTALLED="nftables успешно установлен"
            MSG_TPROXY_NFT_ERROR="Не удалось установить nftables"
            MSG_TPROXY_FW4_REQUIRED="Для TPROXY требуется firewall4 (fw4). Обновите OpenWrt и установите firewall4."
            MSG_PKG_INSTALLING="Установка пакета: %s..."
            MSG_PKG_INSTALLED="Пакет установлен: %s"
            MSG_PKG_INSTALL_ERROR="Не удалось установить пакет: %s"
            MSG_INSTALLING_TUN_MODE="Установка TUN режима..."
            MSG_UNINSTALLING_TUN_MODE="Удаление TUN режима..."
            MSG_TUN_DEPS_INSTALL="Установка зависимостей для TUN режима..."
            MSG_TUN_DEPS_INSTALLED="Зависимости для TUN режима установлены"
            MSG_TUN_DEPS_ALREADY="Зависимости для TUN режима уже установлены"
            MSG_TUN_DEPS_ERROR="Ошибка установки зависимостей для TUN режима"
            MSG_UNINSTALL_EXISTING_FILES="Удаление существующих файлов sing-box..."
            MSG_INVALID_MODE="Ошибка: Некорректный режим"
            MSG_INVALID_MODE_FOUND="Ошибка: Не найден режим для удаления."
            MSG_MODE_FOUND_TPROXY="Найден TPROXY режим"
            MSG_MODE_FOUND_TUN="Найден TUN режим"
            MSG_SINGBOX_CHOOSE="Выберите сборку ядра sing-box:"
            MSG_SINGBOX_OPTION1="1) Original — SagerNet/sing-box (по умолчанию)"
            MSG_SINGBOX_OPTION2="2) Extended — shtorm-7/sing-box-extended"
            MSG_SINGBOX_OPTION3="3) Clean — mrvokintos/sing-box-clean"
            MSG_CLEAN_CHOOSE="Выберите вариант Clean ядра:"
            MSG_CLEAN_OPTION1="1) Origin Clean (по умолчанию)"
            MSG_CLEAN_OPTION2="2) Extended Clean"
            MSG_CLEAN_PROMPT="Введите ваш выбор [1-2, Enter=1]:"
            MSG_SINGBOX_PROMPT="Введите ваш выбор [1-3, Enter=1]:"
            MSG_SINGBOX_ARCH="Архитектура OpenWrt: %s, формат пакета: %s"
            MSG_SINGBOX_RELEASE="Последний релиз %s: %s"
            MSG_SINGBOX_ASSET_MISSING="В релизе %s нет пакета для архитектуры %s (%s)."
            MSG_SINGBOX_RELEASE_ERROR="Не удалось определить последний релиз %s."
            MSG_INVALID_INPUT="Ошибка: Некорректный ввод"
            MSG_SINGBOX_DOWNLOADING="Загрузка '%s' в /tmp..."
            MSG_INVALID_INPUT="Ошибка: Некорректный ввод"
            MSG_REPEAT_INPUT="Повторите ввод"
            MSG_IPV6_DISABLE_PROMPT="Отключить IPv6? [1-Да, 2-Нет] (по умолчанию: 1 - Отключить): "
            MSG_IPV6_SKIP="IPv6 оставлен без изменений"
            MSG_IPV6_RESTORE_CHECK="Проверка необходимости восстановления IPv6..."
            MSG_IPV6_RESTORE_SKIP="IPv6 не был отключён, восстановление не требуется"
            ;;
        *)
            MSG_INSTALL_TITLE="Starting! ($script_name)"
            MSG_UPDATE_PKGS="Updating repositories..."
            MSG_PKGS_SUCCESS="Packages updated successfully"
            MSG_PKGS_ERROR="Error updating packages"
            MSG_INSTALL_SINGBOX="Installing latest sing-box version..."
            MSG_INSTALL_SINGBOX_SUCCESS="Sing-box installed successfully"
            MSG_INSTALL_SINGBOX_ERROR="Error installing sing-box"
            MSG_UNINSTALL_SINGBOX="Uninstalling sing-box..."
            MSG_UNINSTALL_SINGBOX_SUCCESS="Sing-box uninstalled successfully"
            MSG_UNINSTALL_SINGBOX_ERROR="Error uninstalling sing-box"
            MSG_SERVICE_CONFIG="Configuring system service..."
            MSG_SERVICE_APPLIED="Service configuration applied"
            MSG_SERVICE_DISABLED="Service temporarily disabled"
            MSG_CONFIG_RESET="Configuration file preserved"
            MSG_CLEANUP_LIB="Cleaning library..."
            MSG_CLEANUP="Cleaning up files..."
            MSG_CLEANUP_DONE="Files removed!"
            MSG_COMPLETE="Done! ($script_name)"
            MSG_DISABLE_IPV6="Disabling IPv6..."
            MSG_IPV6_DISABLED="IPv6 disabled"
            MSG_START_SERVICE="Starting sing-box service"
            MSG_SERVICE_STARTED="Service started successfully"
            MSG_OPERATION="Select install operation:"
            MSG_INSTALL="1. Install"
            MSG_DELETE="2. Delete"
            MSG_REINSTALL_UPDATE="3. Reinstall/Update"
            MSG_CHOICE="Your choice: "
            MSG_ALREADY_INSTALLED="Error: Package already installed. For reinstall choose option 3"
            MSG_INSTALLING="Installing..."
            MSG_INSTALL_SUCCESS="Install completed"
            MSG_UNINSTALLING="Completely uninstalling..."
            MSG_UNINSTALL_SUCCESS="Uninstalled successfully"
            MSG_NOT_INSTALLED="Error: Package not installed. Nothing to remove."
            MSG_INVALID_OPERATION="Error: Invalid operation"
            MSG_RESTORING_IPV6="Restoring IPv6 settings..."
            MSG_IPV6_RESTORED="IPv6 settings restored"
            MSG_REMOVING_CONFIGS="Removing configuration files..."
            MSG_NETWORK_CHECK="Checking network availability..."
            MSG_NETWORK_SUCCESS="Network available (via %s, in %s sec)"
            MSG_NETWORK_ERROR="Network not available after %s sec!"
            MSG_MODE="Select mode:"
            MSG_TUN="1. TUN"
            MSG_TPROXY="2. TPROXY"
            MSG_MODE_CHOICE="Your choice: "
            MSG_INSTALLING_TPROXY_MODE="Installing TPROXY mode..."
            MSG_UNINSTALLING_TPROXY_MODE="Uninstalling TPROXY mode..."
            MSG_TPROXY_NFT_INSTALL="Installing nftables (nft) for TPROXY..."
            MSG_TPROXY_NFT_INSTALLED="nftables installed successfully"
            MSG_TPROXY_NFT_ERROR="Failed to install nftables"
            MSG_TPROXY_FW4_REQUIRED="TPROXY requires firewall4 (fw4). Please upgrade OpenWrt and install firewall4."
            MSG_PKG_INSTALLING="Installing package: %s..."
            MSG_PKG_INSTALLED="Package installed: %s"
            MSG_PKG_INSTALL_ERROR="Failed to install package: %s"
            MSG_INSTALLING_TUN_MODE="Installing TUN mode..."
            MSG_UNINSTALLING_TUN_MODE="Uninstalling TUN mode..."
            MSG_TUN_DEPS_INSTALL="Installing TUN mode dependencies..."
            MSG_TUN_DEPS_INSTALLED="TUN mode dependencies installed"
            MSG_TUN_DEPS_ALREADY="TUN mode dependencies already installed"
            MSG_TUN_DEPS_ERROR="Failed to install TUN mode dependencies"
            MSG_UNINSTALL_EXISTING_FILES="Uninstalling existing sing-box files..."
            MSG_INVALID_MODE="Error: Invalid mode"
            MSG_INVALID_MODE_FOUND="Error: Mode not found for removal."
            MSG_MODE_FOUND_TPROXY="TPROXY mode found"
            MSG_MODE_FOUND_TUN="TUN mode found"
            MSG_SINGBOX_CHOOSE="Choose the sing-box core build:"
            MSG_SINGBOX_OPTION1="1) Original — SagerNet/sing-box (default)"
            MSG_SINGBOX_OPTION2="2) Extended — shtorm-7/sing-box-extended"
            MSG_SINGBOX_OPTION3="3) Clean — mrvokintos/sing-box-clean"
            MSG_CLEAN_CHOOSE="Choose Clean core variant:"
            MSG_CLEAN_OPTION1="1) Origin Clean (default)"
            MSG_CLEAN_OPTION2="2) Extended Clean"
            MSG_CLEAN_PROMPT="Enter your choice [1-2, Enter=1]:"
            MSG_SINGBOX_PROMPT="Enter your choice [1-3, Enter=1]:"
            MSG_SINGBOX_ARCH="OpenWrt architecture: %s, package format: %s"
            MSG_SINGBOX_RELEASE="Latest %s release: %s"
            MSG_SINGBOX_ASSET_MISSING="Release %s has no package for architecture %s (%s)."
            MSG_SINGBOX_RELEASE_ERROR="Unable to resolve the latest %s release."
            MSG_INVALID_INPUT="Error: Invalid input"
            MSG_SINGBOX_DOWNLOADING="Downloading '%s' to /tmp..."
            MSG_INVALID_INPUT="Error: Invalid input"
            MSG_REPEAT_INPUT="Repeat input"
            MSG_IPV6_DISABLE_PROMPT="Disable IPv6? [1-Yes, 2-No] (default: 1 - Disable): "
            MSG_IPV6_SKIP="IPv6 left unchanged"
            MSG_IPV6_RESTORE_CHECK="Checking if IPv6 restore is needed..."
            MSG_IPV6_RESTORE_SKIP="IPv6 was not disabled, restore not needed"
            ;;
    esac


}

# Обновление репозиториев / Update repos
update_pkgs() {
    show_progress "$MSG_UPDATE_PKGS"
    if pkg_list_update; then
      show_success "$MSG_PKGS_SUCCESS"
    else
      show_error "$MSG_PKGS_ERROR"
      exit 1
    fi
}

ensure_nft_available() {
    if command -v nft >/dev/null 2>&1; then
        return 0
    fi
    if [ -x /usr/sbin/nft ] || [ -x /sbin/nft ]; then
        return 0
    fi
    show_progress "$MSG_TPROXY_NFT_INSTALL"
    if pkg_install nftables; then
        show_success "$MSG_TPROXY_NFT_INSTALLED"
        return 0
    fi
    show_error "$MSG_TPROXY_NFT_ERROR"
    exit 1
}

ensure_fw4_available() {
    if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ]; then
        return 0
    fi
    show_error "$MSG_TPROXY_FW4_REQUIRED"
    exit 1
}

ensure_pkg() {
    local pkg="$1"
    if pkg_is_installed "$pkg"; then
        return 0
    fi
    show_progress "$(printf "$MSG_PKG_INSTALLING" "$pkg")"
    if pkg_install "$pkg"; then
        show_success "$(printf "$MSG_PKG_INSTALLED" "$pkg")"
        return 0
    fi
    show_error "$(printf "$MSG_PKG_INSTALL_ERROR" "$pkg")"
    exit 1
}

ensure_tproxy_deps() {
    ensure_fw4_available
    ensure_nft_available
    ensure_pkg ip-full
    ensure_pkg kmod-nft-tproxy
    ensure_pkg kmod-nft-socket
    ensure_pkg kmod-inet-diag
}

install_mode_deps() {
    case $MODE in
        1)
            show_progress "$MSG_TUN_DEPS_INSTALL"
            if pkg_is_installed "kmod-tun"; then
                show_success "$MSG_TUN_DEPS_ALREADY"
                return 0
            fi
            if pkg_install kmod-tun; then
                show_success "$MSG_TUN_DEPS_INSTALLED"
            else
                show_error "$MSG_TUN_DEPS_ERROR"
                exit 1
            fi
            ;;
        2)
            ensure_tproxy_deps
            ;;
    esac
}

# Выбор операции установки / Choose install operation
choose_install_operation() {
    if [ -z "$OPERATION" ]; then
        while true; do
            show_message "$MSG_OPERATION"
            show_message "$MSG_INSTALL"
            show_message "$MSG_DELETE"
            show_message "$MSG_REINSTALL_UPDATE"
            read_input "$MSG_CHOICE" OPERATION
            case "$OPERATION" in
                1|2|3)
                    break
                    ;;
                *)
                    show_error "$MSG_INVALID_INPUT. $MSG_REPEAT_INPUT"
                    ;;
            esac
        done
    fi
}

# Проверка доступности сети / Network availability check
network_check() {
    local timeout=500
    local interval=5
    local targets="223.5.5.5 180.76.76.76 77.88.8.8 1.1.1.1 8.8.8.8 9.9.9.9 94.140.14.14"

    local attempts=$((timeout / interval))
    local success=0
    local i=2

    show_progress "$MSG_NETWORK_CHECK"
    sleep "$interval"

    while [ $i -lt $attempts ]; do
        local num_targets=$(echo "$targets" | wc -w)
        local index=$((i % num_targets))
        local target=$(echo "$targets" | cut -d' ' -f$((index + 1)))

        if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
            success=1
            break
        fi

        sleep "$interval"
        i=$((i + 1))
    done

    if [ $success -eq 1 ]; then
        local total_time=$((i * interval))
        show_success "$(printf "$MSG_NETWORK_SUCCESS" "$target" "$total_time")"
    else
        show_error "$(printf "$MSG_NETWORK_ERROR" "$timeout")" >&2
        exit 1
    fi
}

# Установка sing-box / Install sing-box
fetch_text() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    else
        wget -qO- "$1"
    fi
}

download_file() {
    if command -v curl >/dev/null 2>&1; then
        curl -fL --max-time 300 -o "$2" "$1"
    else
        wget -O "$2" "$1"
    fi
}

detect_openwrt_arch() {
    local arch=""
    if [ -r /etc/openwrt_release ]; then
        . /etc/openwrt_release
        arch="${DISTRIB_ARCH:-}"
    fi
    if [ -z "$arch" ] && [ -r /etc/apk/arch ]; then
        arch=$(sed -n '1p' /etc/apk/arch)
    fi
    if [ -z "$arch" ] && command -v opkg >/dev/null 2>&1; then
        arch=$(opkg print-architecture 2>/dev/null | awk 'END { print $2 }')
    fi
    case "$arch" in
        ''|*[!A-Za-z0-9._+-]*) return 1 ;;
    esac
    printf '%s\n' "$arch"
}

install_release_core() {
    local repo="$1"
    local label="$2"
    local package_name="$3"
    local fixed_tag="${4:-}"
    local arch latest_html tag assets asset_path asset_url package_file

    arch=$(detect_openwrt_arch) || {
        show_error "$(printf "$MSG_SINGBOX_RELEASE_ERROR" "$label")"
        return 1
    }
    show_message "$(printf "$MSG_SINGBOX_ARCH" "$arch" "$PKG_EXT")"

    if [ -n "$fixed_tag" ]; then
        tag="$fixed_tag"
    else
        latest_html=$(fetch_text "https://github.com/${repo}/releases/latest") || {
            show_error "$(printf "$MSG_SINGBOX_RELEASE_ERROR" "$label")"
            return 1
        }
        tag=$(printf '%s' "$latest_html" | grep -o 'releases/expanded_assets/[^"?]*' | head -n 1 | sed 's#releases/expanded_assets/##')
    fi
    [ -n "$tag" ] || {
        show_error "$(printf "$MSG_SINGBOX_RELEASE_ERROR" "$label")"
        return 1
    }
    show_message "$(printf "$MSG_SINGBOX_RELEASE" "$label" "$tag")"

    assets=$(fetch_text "https://github.com/${repo}/releases/expanded_assets/${tag}") || return 1

    if [ "$package_name" = "sing-box" ]; then
        asset_path=$(printf '%s' "$assets" | grep -o 'href="[^"]*"' | sed 's/^href="//;s/"$//' | grep -v 'sing-box-extended' | grep -E "(sing-box|sing_box).*_openwrt_${arch}\.${PKG_EXT}$" | head -n 1)
        if [ -z "$asset_path" ]; then
            asset_path=$(printf '%s' "$assets" | grep -o 'href="[^"]*"' | sed 's/^href="//;s/"$//' | grep -v 'sing-box-extended' | grep "_openwrt_${arch}\.${PKG_EXT}$" | head -n 1)
        fi
    else
        asset_path=$(printf '%s' "$assets" | grep -o 'href="[^"]*"' | sed 's/^href="//;s/"$//' | grep 'sing-box-extended' | grep "_openwrt_${arch}\.${PKG_EXT}$" | head -n 1)
    fi

    [ -n "$asset_path" ] || {
        show_error "$(printf "$MSG_SINGBOX_ASSET_MISSING" "$tag" "$arch" "$PKG_EXT")"
        return 1
    }

    asset_url="https://github.com${asset_path}"
    package_file="/tmp/${package_name}.${PKG_EXT}"
    show_progress "$(printf "$MSG_SINGBOX_DOWNLOADING" "${asset_path##*/}")"
    download_file "$asset_url" "$package_file" || return 1

    if [ "$package_name" = "sing-box" ]; then
        pkg_is_installed sing-box-extended && pkg_remove sing-box-extended || true
    else
        pkg_is_installed sing-box && pkg_remove sing-box || true
    fi

    if pkg_install_file "$package_file"; then
        rm -f "$package_file"
        mkdir -p /etc/singbox-ui
        printf '%s\n' "$repo" > /etc/singbox-ui/core-source
        show_success "$MSG_INSTALL_SINGBOX_SUCCESS"
        return 0
    fi
    rm -f "$package_file"
    return 1
}

install_singbox() {
    show_progress "$MSG_INSTALL_SINGBOX"
    if [ -z "$SINGBOX_INSTALL_MODE" ]; then
        while true; do
            show_message ""
            show_message "$MSG_SINGBOX_CHOOSE"
            show_message "$MSG_SINGBOX_OPTION1"
            show_message "$MSG_SINGBOX_OPTION2"
            show_message "$MSG_SINGBOX_OPTION3"
            show_message ""
            read_input "$MSG_SINGBOX_PROMPT" SINGBOX_INSTALL_MODE
            SINGBOX_INSTALL_MODE="${SINGBOX_INSTALL_MODE:-1}"
            case "$SINGBOX_INSTALL_MODE" in
                1|2|3) break ;;
                *) show_error "$MSG_INVALID_INPUT. $MSG_REPEAT_INPUT" ;;
            esac
        done
    fi

    case "$SINGBOX_INSTALL_MODE" in
        1)
            install_release_core "SagerNet/sing-box" "Original" "sing-box"
            ;;
        2)
            install_release_core "shtorm-7/sing-box-extended" "Extended" "sing-box-extended"
            ;;
        3)
            local clean_choice=""
            while true; do
                show_message ""
                show_message "$MSG_CLEAN_CHOOSE"
                show_message "$MSG_CLEAN_OPTION1"
                show_message "$MSG_CLEAN_OPTION2"
                show_message ""
                read_input "$MSG_CLEAN_PROMPT" clean_choice
                clean_choice="${clean_choice:-1}"
                case "$clean_choice" in
                    1|2) break ;;
                    *) show_error "$MSG_INVALID_INPUT. $MSG_REPEAT_INPUT" ;;
                esac
            done

            if [ "$clean_choice" = "1" ]; then
                install_release_core "mrvokintos/sing-box-clean" "Origin Clean" "sing-box" "latest"
            else
                install_release_core "mrvokintos/sing-box-clean" "Extended Clean" "sing-box-extended" "latest"
            fi
            ;;
    esac || {
        show_error "$MSG_INSTALL_SINGBOX_ERROR"
        exit 1
    }
}

# Удаление sing-box / Uninstall sing-box
uninstall_singbox() {
    show_progress "$MSG_UNINSTALL_SINGBOX"
    service sing-box stop 2>/dev/null
    service sing-box disable 2>/dev/null
    local removed=0
    if pkg_is_installed sing-box-extended; then
        pkg_remove sing-box-extended && removed=1
    elif pkg_is_installed sing-box; then
        pkg_remove sing-box && removed=1
    fi
    if [ "$removed" -eq 1 ]; then
        show_success "$MSG_UNINSTALL_SINGBOX_SUCCESS"
    else
        show_error "$MSG_UNINSTALL_SINGBOX_ERROR"
        exit 1
    fi
}

# Конфигурация сервиса / Service configuration
configure_singbox_service() {
    show_progress "$MSG_SERVICE_CONFIG"
    uci set sing-box.main.enabled="1"
    uci set sing-box.main.user="root"
    uci commit sing-box
    show_success "$MSG_SERVICE_APPLIED"
}

# Отключение сервиса / Disable service
disable_singbox_service() {
    show_progress "$MSG_SERVICE_DISABLED"
    service sing-box disable
    show_success "$MSG_SERVICE_DISABLED"
}

# Очистка конфигурации / Reset configuration
clean_singbox_config() {
    show_progress "$MSG_CONFIG_RESET"
    mkdir -p /etc/sing-box
    [ -s /etc/sing-box/config.json ] || printf '{}\n' > /etc/sing-box/config.json
    show_success "$MSG_CONFIG_RESET"
}

# Отключение IPv6 / Disable IPv6
disabled_ipv6() {
    show_progress "$MSG_DISABLE_IPV6"
    uci set 'network.lan.ipv6=0'
    uci set 'network.wan.ipv6=0'
    uci set 'dhcp.lan.dhcpv6=disabled'
    /etc/init.d/odhcpd disable
    uci commit
    show_success "$MSG_IPV6_DISABLED"
}

# Восстановление IPv6 / Restore IPv6
restore_ipv6() {
    show_progress "$MSG_RESTORING_IPV6"
    uci set 'network.lan.ipv6=1'
    uci set 'network.wan.ipv6=1'
    uci set 'dhcp.lan.dhcpv6=server'
    /etc/init.d/odhcpd enable
    uci commit
    show_success "$MSG_IPV6_RESTORED"
}

# Спросить пользователя про отключение IPv6 (дефолт — отключить) / Ask user about IPv6 disable (default — disable)
maybe_disable_ipv6() {
    while true; do
        read_input "$MSG_IPV6_DISABLE_PROMPT" IPV6_CHOICE
        if [ -z "$IPV6_CHOICE" ]; then
            IPV6_CHOICE="1"
        fi
        case "$IPV6_CHOICE" in
            1)
                disabled_ipv6
                break
                ;;
            2)
                show_progress "$MSG_IPV6_SKIP"
                break
                ;;
            *)
                show_error "$MSG_INVALID_INPUT. $MSG_REPEAT_INPUT"
                ;;
        esac
    done
}

# Восстановить IPv6 только если он был отключён / Restore IPv6 only if it was disabled
maybe_restore_ipv6() {
    show_progress "$MSG_IPV6_RESTORE_CHECK"
    local ipv6_val
    ipv6_val=$(uci -q get network.lan.ipv6 2>/dev/null)
    if [ "$ipv6_val" = "0" ]; then
        restore_ipv6
    else
        show_progress "$MSG_IPV6_RESTORE_SKIP"
    fi
}

# Включение sing-box / Enable sing-box
enable_singbox() {
    show_progress "$MSG_START_SERVICE"
    service sing-box enable
    service sing-box start
    show_success "$MSG_SERVICE_STARTED"
}

# Проверка установки / Check installation
check_installed() {
    pkg_is_installed sing-box || pkg_is_installed sing-box-extended
}

# Удаление конфигураций / Remove configurations
remove_singbox_data() {
    show_progress "$MSG_REMOVING_CONFIGS"
    uci -q delete sing-box
    uci commit sing-box
    [ -f /etc/sing-box/config.json ] && rm -f /etc/sing-box/config.json
    [ -f /etc/config/sing-box ] && rm -f /etc/config/sing-box
}

# Удаление существующих файлов / Remove existing files
uninstall_existing_files(){
    show_progress "$MSG_UNINSTALL_EXISTING_FILES"
    [ -f /etc/config/sing-box.old ] && rm -f /etc/config/sing-box.old
}

# Выбор режима / Choose mode
choose_mode() {
    if [ -z "$MODE" ]; then
        while true; do
            show_message "$MSG_MODE"
            show_message "$MSG_TUN"
            show_message "$MSG_TPROXY"
            read_input "$MSG_MODE_CHOICE" MODE
            case "$MODE" in
                1|2)
                    break
                    ;;
                *)
                    show_error "$MSG_INVALID_MODE. $MSG_REPEAT_INPUT"
                    ;;
            esac
        done
    fi
}

definition_mode() {
    if [ -f /etc/sing-box/tproxy.nft ]; then
        show_progress "$MSG_MODE_FOUND_TPROXY"
        MODE=2
    elif uci -q get network.proxy.device | grep -q "singtun0"; then
        show_progress "$MSG_MODE_FOUND_TUN"
        MODE=1
    else
        show_error "$MSG_INVALID_MODE_FOUND"
    fi
}

# Установка tun mode / Install tun mode
installed_tun_mode() {
    show_progress "$MSG_INSTALLING_TUN_MODE"
    "$MODE_SWITCH" enable-tun
    network_check
    enable_singbox
}

# Удаление tun mode / Uninstall tun mode
uninstalled_tun_mode() {
    show_progress "$MSG_UNINSTALLING_TUN_MODE"
    "$MODE_SWITCH" disable-tun
    network_check
}

# Установка tproxy mode / Install tproxy mode
installed_tproxy_mode() {
    show_progress "$MSG_INSTALLING_TPROXY_MODE"
    enable_singbox
    "$MODE_SWITCH" enable-tproxy
    network_check
}

# Удаление tproxy mode / Uninstall tproxy mode
uninstalled_tproxy_mode() {
    show_progress "$MSG_UNINSTALLING_TPROXY_MODE"
    "$MODE_SWITCH" disable-tproxy
}

# Выбор режима установки / Choose install mode
perform_install_mode() {
    case $MODE in
        1)
            installed_tun_mode
            ;;
        2)
            installed_tproxy_mode
            ;;
        *)
            show_error "$MSG_INVALID_MODE"
            exit 1
            ;;
    esac
}

# Выбор режима установки / Choose install mode
perform_uninstall_mode() {
    case $MODE in
        1)
            uninstalled_tun_mode
            ;;
        2)
            uninstalled_tproxy_mode
            ;;
        *)
            show_error "$MSG_INVALID_MODE"
            ;;
    esac
}

# Установка / Install
install() {
    show_progress "$MSG_INSTALLING"
    choose_mode
    install_mode_deps
    install_singbox
    configure_singbox_service
    disable_singbox_service
    clean_singbox_config
    perform_install_mode
    maybe_disable_ipv6
    network_check
    show_success "$MSG_INSTALL_SUCCESS"
}

# Удаление / Uninstall
uninstall() {
    show_progress "$MSG_UNINSTALLING"
    definition_mode
    uninstall_singbox
    perform_uninstall_mode
    unset MODE
    remove_singbox_data
    uninstall_existing_files
    maybe_restore_ipv6
    network_check
    show_success "$MSG_UNINSTALL_SUCCESS"
}

# Выполнение операций / Perform operations
perform_operation() {
    case $OPERATION in
        1)  
            if check_installed; then
                show_error "$MSG_ALREADY_INSTALLED"
                exit 1
            fi
            install
            ;;
        2)  
            if ! check_installed; then
                show_error "$MSG_NOT_INSTALLED"
                exit 1
            fi
            uninstall
            ;;
        3)  
            if check_installed; then
                uninstall
            fi
            update_pkgs
            install
            ;;
        *)
            show_error "$MSG_INVALID_OPERATION"
            exit 1
            ;;
    esac
}

# Очистка / Cleanup
cleanup() {
    show_progress "$MSG_CLEANUP"
    rm -- "$0"
    show_success "$MSG_CLEANUP_DONE"
}

# Завершение скрипта / Complete script
complete_script() {
    show_success "$MSG_COMPLETE"
    cleanup
}

# ======== Основной код / Main code ========

run_steps_with_separator \
    init_language

run_steps_with_separator \
    "::$MSG_INSTALL_TITLE" \
    update_pkgs \
    choose_install_operation \
    perform_operation \
    complete_script
