#!/bin/sh
# Версия панели в JS совпадает с PKG_VERSION / The JS panel version matches PKG_VERSION
set -eu
mk=$(sed -n 's/^PKG_VERSION:=//p' luci-app-singbox-ui/Makefile)
js=$(sed -n "s/^const UI_VERSION='\([^']*\)'.*/\1/p" luci-app-singbox-ui/htdocs/luci-static/resources/view/singbox-ui/singbox-ui.js)
[ "$mk" = "$js" ] || { echo "FAIL: Makefile $mk != singbox-ui.js $js" >&2; exit 1; }
echo "version tests: ok ($mk)"
