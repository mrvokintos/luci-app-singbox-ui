#!/bin/sh
set -eu

test_root="$(mktemp -d)"
fragment="/tmp/.sbui-helper-test-$$-0"
trap 'rm -rf "$test_root"; rm -f "$fragment"' EXIT

helper='luci-app-singbox-ui/root/usr/libexec/singbox-ui-helper'
export SINGBOX_UI_CONFIG_DIR="$test_root/sing-box"
export SINGBOX_UI_TEMPLATE_FILE="$test_root/template.json"
export SINGBOX_UI_TEMPLATE_DIR="$test_root/templates"

sh "$helper" ensure-dir
[ -d "$SINGBOX_UI_TEMPLATE_DIR" ]
printf '%s\n' '{"outbounds":[{"type":"direct","tag":"proxy"}]}' > "$SINGBOX_UI_CONFIG_DIR/named.json"
sh "$helper" activate named.json
cmp "$SINGBOX_UI_CONFIG_DIR/named.json" "$SINGBOX_UI_CONFIG_DIR/config.json"

payload='{"outbounds":[{"type":"vless","tag":"proxy"}]}'
printf '%s' "$payload" | base64 > "$fragment"
sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_CONFIG_DIR/generated.json"
[ "$(cat "$SINGBOX_UI_CONFIG_DIR/generated.json")" = "$payload" ]

printf '%s' "$payload" | base64 > "$fragment"
sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_TEMPLATE_DIR/custom.json"
[ "$(cat "$SINGBOX_UI_TEMPLATE_DIR/custom.json")" = "$payload" ]

printf '%s' "$payload" | base64 > "$fragment"
if sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_TEMPLATE_DIR/../escape.json" 2>/dev/null; then
	echo 'helper accepted an unsafe template path' >&2
	exit 1
fi

echo 'singbox-ui helper: passed'
