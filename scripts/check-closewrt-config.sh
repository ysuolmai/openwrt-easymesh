#!/bin/sh

set -eu

config_name="${1:?config name required}"
config_file="${2:-.config}"
openwrt_dir="$(cd "$(dirname "$config_file")" && pwd)"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
expected_config="$repo_dir/configs/$config_name.txt"
filogic_mk="$openwrt_dir/target/linux/mediatek/image/filogic.mk"

[ -f "$config_file" ] || {
	echo "missing config file: $config_file" >&2
	exit 1
}

missing=0
require_symbol() {
	local symbol="$1"
	if ! grep -q "^${symbol}=y$" "$config_file"; then
		echo "missing required config: ${symbol}=y" >&2
		missing=1
	fi
}

require_expected_device_symbols() {
	local prefix="$1"
	local label="$2"
	local symbols
	local symbol

	if [ ! -f "$expected_config" ]; then
		echo "missing expected config for ${label}: ${expected_config}" >&2
		missing=1
		return
	fi

	symbols="$(sed -n "s/^\(${prefix}[^=]*\)=y$/\1/p" "$expected_config")"
	if [ -z "$symbols" ]; then
		echo "missing expected device symbols for ${label}: ${expected_config}" >&2
		missing=1
		return
	fi

	for symbol in $symbols; do
		require_symbol "$symbol"
	done
}

require_file_contains() {
	local file="$1"
	local token="$2"
	local label="$3"

	if [ ! -f "$file" ]; then
		echo "missing required source file for ${label}: ${file}" >&2
		missing=1
		return
	fi
	if ! grep -Eq "(^|[[:space:]])${token}([[:space:]]|$)" "$file"; then
		echo "missing required source support: ${label}" >&2
		missing=1
	fi
}

require_common_mesh_packages() {
	require_symbol CONFIG_PACKAGE_wpad-openssl
	require_symbol CONFIG_PACKAGE_kmod-batman-adv
	require_symbol CONFIG_PACKAGE_batctl-default
	require_symbol CONFIG_PACKAGE_dawn
	require_symbol CONFIG_PACKAGE_umdns
	require_symbol CONFIG_PACKAGE_jsonfilter
	require_symbol CONFIG_PACKAGE_curl
	require_symbol CONFIG_PACKAGE_iw
	require_symbol CONFIG_PACKAGE_ip-bridge
	require_symbol CONFIG_PACKAGE_iwinfo
}

require_closewrt_mt7981_target() {
	require_symbol CONFIG_TARGET_mediatek
	require_symbol CONFIG_TARGET_mediatek_filogic
	require_expected_device_symbols \
		CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_ \
		"CloseWRT-CI MT7981 device list"

	require_symbol CONFIG_MTK_CONNINFRA_APSOC
	require_symbol CONFIG_MTK_CONNINFRA_APSOC_MT7981
	require_symbol CONFIG_MTK_FIRST_IF_MT7981
	require_symbol CONFIG_PACKAGE_luci-app-mtwifi-cfg
	require_symbol CONFIG_PACKAGE_luci-app-turboacc-mtk
	require_symbol CONFIG_PACKAGE_kmod-conninfra
	require_symbol CONFIG_PACKAGE_kmod-mt_wifi
	require_symbol CONFIG_PACKAGE_kmod-warp
	require_symbol CONFIG_PACKAGE_kmod-mediatek_hnat
	require_symbol CONFIG_PACKAGE_wifi-scripts
	require_symbol CONFIG_PACKAGE_wifi-dats

	require_file_contains "$filogic_mk" "define Device/sx_7981r128" "sx_7981r128 injected device profile"
}

require_ac_packages() {
	require_symbol CONFIG_PACKAGE_luci
	require_symbol CONFIG_PACKAGE_luci-ssl
	require_symbol CONFIG_PACKAGE_easymesh-controller
	require_symbol CONFIG_PACKAGE_easymesh-local-member
	require_symbol CONFIG_PACKAGE_easymesh-agent
	require_symbol CONFIG_PACKAGE_luci-app-easymesh
	require_symbol CONFIG_PACKAGE_luci-theme-shadcn
	require_symbol CONFIG_PACKAGE_jshn
	require_symbol CONFIG_PACKAGE_umdns
}

require_ap_packages() {
	require_symbol CONFIG_PACKAGE_luci
	require_symbol CONFIG_PACKAGE_luci-ssl
	require_symbol CONFIG_PACKAGE_luci-theme-shadcn
	require_symbol CONFIG_PACKAGE_easymesh-agent
}

case "$config_name" in
	CLOSEWRT-MT7981-MESH-AC)
		require_closewrt_mt7981_target
		require_common_mesh_packages
		require_ac_packages
		;;
	CLOSEWRT-MT7981-MESH-AP)
		require_closewrt_mt7981_target
		require_common_mesh_packages
		require_ap_packages
		;;
	*)
		echo "unknown config target: $config_name" >&2
		missing=1
		;;
esac

[ "$missing" = "0" ] || exit 1

echo "required CloseWRT mesh config symbols present for $config_name"
