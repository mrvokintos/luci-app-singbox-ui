#!/bin/sh
# Откуда берутся панель, ядро Clean и пакеты. Форку достаточно поменять эти
# строки (или задать переменные окружения): остальной код берёт адреса отсюда.
# Where the panel, the Clean core and the packages come from. A fork only needs
# to change these lines (or set the environment variables): the rest of the
# code takes its URLs from here.

: "${SBUI_GITHUB_REPO:=mrvokintos/luci-app-singbox-ui}"
: "${SBUI_CORE_REPO:=mrvokintos/sing-box-clean}"
: "${REPO_BASE:=https://openwrt.mrvokintos.ru}"
: "${ARTIFACTS_URL:=https://raw.githubusercontent.com/$SBUI_GITHUB_REPO/artifacts}"
export SBUI_GITHUB_REPO SBUI_CORE_REPO REPO_BASE ARTIFACTS_URL
