#!/bin/sh
set -eu

test_root="$(mktemp -d)"
fragment="/tmp/.sbui-helper-test-$$-0"
trap 'rm -rf "$test_root"; rm -f /tmp/.sbui-helper-test-$$-*' EXIT

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
printf '%s' "$payload" > "$fragment"
sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_CONFIG_DIR/generated.json"
[ "$(cat "$SINGBOX_UI_CONFIG_DIR/generated.json")" = "$payload" ]

printf '%s' "$payload" > "$fragment"
sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_TEMPLATE_DIR/custom.json"
[ "$(cat "$SINGBOX_UI_TEMPLATE_DIR/custom.json")" = "$payload" ]

printf '%s' "$payload" > "$fragment"
if sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_TEMPLATE_DIR/../escape.json" 2>/dev/null; then
	echo 'helper accepted an unsafe template path' >&2
	exit 1
fi

# Fragments split in the middle of a multibyte character are joined back exactly.
second="/tmp/.sbui-helper-test-$$-1"
printf '{"name":"\320' > "$fragment"
printf '\237"}' > "$second"
sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_CONFIG_DIR/generated.json"
[ "$(cat "$SINGBOX_UI_CONFIG_DIR/generated.json")" = '{"name":"П"}' ]
[ ! -e "$fragment" ] && [ ! -e "$second" ]

before="$(cat "$SINGBOX_UI_CONFIG_DIR/generated.json")"
# An unreadable fragment must not damage the existing file (root reads anything).
if [ "$(id -u)" -ne 0 ]; then
	printf '%s' "$payload" > "$fragment"
	chmod 000 "$fragment"
	if sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_CONFIG_DIR/generated.json" 2>/dev/null; then
		echo 'helper accepted an unreadable fragment' >&2
		exit 1
	fi
	[ "$(cat "$SINGBOX_UI_CONFIG_DIR/generated.json")" = "$before" ]
	[ ! -e "$fragment" ]
fi
if ls "$SINGBOX_UI_CONFIG_DIR"/*.sbui-tmp.* >/dev/null 2>&1; then
	echo 'helper left a temp file behind' >&2
	exit 1
fi

if sh "$helper" merge "/tmp/.sbui-helper-test-$$-" "$SINGBOX_UI_CONFIG_DIR/generated.json" 2>/dev/null; then
	echo 'helper accepted a merge without fragments' >&2
	exit 1
fi
[ "$(cat "$SINGBOX_UI_CONFIG_DIR/generated.json")" = "$before" ]

if command -v ucode >/dev/null 2>&1; then
	# read-chunk returns <= 64 KiB pieces that never split a UTF-8 sequence.
	big="$SINGBOX_UI_CONFIG_DIR/big.json"
	i=0; : > "$big"
	while [ "$i" -lt 30000 ]; do printf 'я😀'; i=$((i + 1)); done >> "$big"
	out="$test_root/joined"; : > "$out"; offset=0
	while :; do
		sh "$helper" read-chunk "$big" "$offset" > "$test_root/chunk"
		size=$(wc -c < "$test_root/chunk")
		[ "$size" -eq 0 ] && break
		[ "$size" -le 65536 ]
		cat "$test_root/chunk" >> "$out"
		offset=$((offset + size))
	done
	cmp "$big" "$out"
	if sh "$helper" read-chunk /etc/passwd 0 >/dev/null 2>&1; then
		echo 'helper read a file outside the allowed directories' >&2
		exit 1
	fi
else
	echo 'ucode not found: skipping read-chunk test'
fi

echo 'singbox-ui helper: passed'
