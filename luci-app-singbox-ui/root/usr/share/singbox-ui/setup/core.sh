#!/bin/sh
# Ядро sing-box: определение и установка / sing-box core: detection and install.
# Варианты / kinds: original | extended | clean | clean-extended
#   original       SagerNet/sing-box (GitHub release)
#   extended       shtorm-7/sing-box-extended (GitHub release)
#   clean          mrvokintos/sing-box-clean: из репозитория, если для архитектуры
#                  есть сборка, иначе с GitHub / from the repo when built for the
#                  arch, otherwise from GitHub
#   clean-extended то же для extended / same for extended
# Источник пишется в /etc/singbox-ui/core-source ("repo" или имя GitHub-репозитория).
# Требует ui.sh, pkg.sh, repo.sh, i18n.sh.

CORE_SOURCE_FILE="$SBUI_ROOT/etc/singbox-ui/core-source"

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

core_kind_valid() {
    case "$1" in original|extended|clean|clean-extended|keep) return 0 ;; esac
    return 1
}

# Имя установленного пакета ядра или пусто / Installed core package name or empty
core_installed_pkg() {
    if pkg_is_installed sing-box-extended; then
        echo sing-box-extended
    elif pkg_is_installed sing-box; then
        echo sing-box
    fi
}

core_version() {
    command -v sing-box >/dev/null 2>&1 || return 0
    sing-box version 2>/dev/null | sed -n '1s/^sing-box version //p'
}

core_source() {
    cat "$CORE_SOURCE_FILE" 2>/dev/null || true
}

# Вариант установленного ядра для меню / Kind of the installed core
core_installed_kind() {
    local pkg src
    pkg=$(core_installed_pkg)
    [ -n "$pkg" ] || return 0
    src=$(core_source)
    case "$src:$pkg" in
        SagerNet/sing-box:*) echo original ;;
        shtorm-7/sing-box-extended:*) echo extended ;;
        repo:sing-box|"$SBUI_CORE_REPO":sing-box) echo clean ;;
        repo:sing-box-extended|"$SBUI_CORE_REPO":sing-box-extended) echo clean-extended ;;
        *:sing-box-extended) echo extended ;;
        *) echo feed ;;
    esac
}

# Нужен ли фид ядер репозитория для варианта / Whether the kind uses the repo core feed
core_kind_uses_repo() {
    case "$1" in
        clean|clean-extended) repo_arch_has_core "$2" ;;
        *) return 1 ;;
    esac
}

_core_set_source() {
    mkdir -p "${CORE_SOURCE_FILE%/*}"
    printf '%s\n' "$1" > "$CORE_SOURCE_FILE"
}

_core_remove_other() {
    if [ "$1" = sing-box ]; then
        pkg_is_installed sing-box-extended && pkg_remove sing-box-extended
    else
        pkg_is_installed sing-box && pkg_remove sing-box
    fi
    return 0
}

# core_install_from_repo PKG — фид ядер уже должен быть записан
# The core feed must already be configured.
core_install_from_repo() {
    local pkg="$1"
    show_progress "$(printf "$MSG_CORE_FROM_REPO" "$pkg")"
    if [ -n "${SETUP_DRY_RUN:-}" ]; then
        echo "[dry-run] install $pkg from repo"
        return 0
    fi
    _core_remove_other "$pkg"
    pkg_install "$pkg" || return 1
    _core_set_source repo
}

# install_release_core REPO LABEL PACKAGE — пакет из последнего GitHub-релиза
# Package from the latest GitHub release.
install_release_core() {
    local repo="$1" label="$2" package_name="$3"
    local arch latest_html tag assets asset_path package_file

    arch=$(detect_openwrt_arch) || {
        show_error "$(printf "$MSG_CORE_RELEASE_ERROR" "$label")"
        return 1
    }
    if [ -n "${SETUP_DRY_RUN:-}" ]; then
        echo "[dry-run] install $label ($repo, $package_name) for $arch"
        return 0
    fi
    latest_html=$(fetch_text "https://github.com/${repo}/releases/latest") || {
        show_error "$(printf "$MSG_CORE_RELEASE_ERROR" "$label")"
        return 1
    }
    tag=$(printf '%s' "$latest_html" | grep -o 'releases/expanded_assets/[^"?]*' | head -n 1 | sed 's#releases/expanded_assets/##')
    [ -n "$tag" ] || {
        show_error "$(printf "$MSG_CORE_RELEASE_ERROR" "$label")"
        return 1
    }
    show_message "$(printf "$MSG_CORE_RELEASE" "$label" "$tag")"

    assets=$(fetch_text "https://github.com/${repo}/releases/expanded_assets/${tag}" |
        grep -o 'href="[^"]*"' | sed 's/^href="//;s/"$//') || return 1

    if [ "$package_name" = sing-box ]; then
        asset_path=$(printf '%s\n' "$assets" | grep -v 'sing-box-extended' | grep -E "(sing-box|sing_box).*_openwrt_${arch}\.${PKG_EXT}$" | head -n 1)
        [ -n "$asset_path" ] || asset_path=$(printf '%s\n' "$assets" | grep -v 'sing-box-extended' | grep "_openwrt_${arch}\.${PKG_EXT}$" | head -n 1)
        [ -n "$asset_path" ] || asset_path=$(printf '%s\n' "$assets" | grep -v 'sing-box-extended' | grep -E "/(sing-box|sing_box)([-_][^/]*)?\.${PKG_EXT}$" | head -n 1)
    else
        asset_path=$(printf '%s\n' "$assets" | grep 'sing-box-extended' | grep "_openwrt_${arch}\.${PKG_EXT}$" | head -n 1)
        [ -n "$asset_path" ] || asset_path=$(printf '%s\n' "$assets" | grep -E "/sing-box-extended([-_][^/]*)?\.${PKG_EXT}$" | head -n 1)
    fi
    [ -n "$asset_path" ] || {
        show_error "$(printf "$MSG_CORE_ASSET_MISSING" "$tag" "$arch" "$PKG_EXT")"
        return 1
    }

    package_file="/tmp/${package_name}.${PKG_EXT}"
    show_progress "$(printf "$MSG_CORE_DOWNLOADING" "${asset_path##*/}")"
    download_file "https://github.com${asset_path}" "$package_file" || return 1

    _core_remove_other "$package_name"
    if pkg_install_file "$package_file"; then
        rm -f "$package_file"
        _core_set_source "$repo"
        return 0
    fi
    rm -f "$package_file"
    return 1
}

# core_install KIND ARCH
core_install() {
    local kind="$1" arch="$2"
    case "$kind" in
        original) install_release_core SagerNet/sing-box Original sing-box ;;
        extended) install_release_core shtorm-7/sing-box-extended Extended sing-box-extended ;;
        clean)
            if repo_arch_has_core "$arch"; then
                core_install_from_repo sing-box
            else
                install_release_core "$SBUI_CORE_REPO" "Clean" sing-box
            fi
            ;;
        clean-extended)
            if repo_arch_has_core "$arch"; then
                core_install_from_repo sing-box-extended
            else
                install_release_core "$SBUI_CORE_REPO" "Clean Extended" sing-box-extended
            fi
            ;;
        *) return 1 ;;
    esac
}

core_uninstall() {
    local pkg
    pkg=$(core_installed_pkg)
    [ -n "$pkg" ] || return 0
    if [ -n "${SETUP_DRY_RUN:-}" ]; then
        echo "[dry-run] remove $pkg"
        return 0
    fi
    service sing-box stop 2>/dev/null
    service sing-box disable 2>/dev/null
    pkg_remove "$pkg" && rm -f "$CORE_SOURCE_FILE"
}
