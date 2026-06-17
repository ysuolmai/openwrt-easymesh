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

require_config_value() {
	local key="$1"
	local value="$2"
	if ! grep -q "^${key}=${value}$" "$config_file"; then
		echo "missing required config: ${key}=${value}" >&2
		missing=1
	fi
}

require_expected_device_symbols() {
	local prefix="$1"
	local label="$2"
	local source_file="${3:-}"
	local symbols
	local symbol
	local device

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
		if grep -q "^${symbol}=y$" "$config_file"; then
			continue
		fi

		device="${symbol#${prefix}}"
		if [ -n "$source_file" ] &&
			[ -f "$source_file" ] &&
			! grep -Eq "(^|[[:space:]])(define Device/${device}|TARGET_DEVICES[[:space:]]*\+=[[:space:]]*${device})([[:space:]]|$)" "$source_file"; then
			echo "warning: skipping unsupported target device from ${label}: ${device}" >&2
			continue
		fi

		echo "missing required config: ${symbol}=y" >&2
		missing=1
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
		"CloseWRT-CI MT7981 device list" \
		"$filogic_mk"

	require_symbol CONFIG_MTK_CONNINFRA_APSOC
	require_symbol CONFIG_MTK_CONNINFRA_APSOC_MT7981
	require_symbol CONFIG_MTK_FIRST_IF_MT7981
	require_symbol CONFIG_first_card
	require_symbol CONFIG_MTK_SUPPORT_OPENWRT
	require_symbol CONFIG_MTK_WIFI_DRIVER
	require_config_value CONFIG_MTK_MT_WIFI m
	require_config_value CONFIG_MTK_WIFI_MODE_AP m
	require_config_value CONFIG_MTK_MT_AP_SUPPORT m
	require_symbol CONFIG_MTK_WIFI_BASIC_FUNC
	require_config_value CONFIG_MTK_MT_WIFI_PATH '"mt_wifi"'
	require_symbol CONFIG_MTK_FIRST_IF_EEPROM_FLASH
	require_config_value CONFIG_MTK_RT_FIRST_CARD_EEPROM '"flash"'
	require_symbol CONFIG_MTK_SECOND_IF_NONE
	require_symbol CONFIG_MTK_THIRD_IF_NONE
	require_symbol CONFIG_MTK_WIFI_FW_BIN_LOAD
	require_config_value CONFIG_MTK_WHNAT_SUPPORT m
	require_symbol CONFIG_MTK_WARP_V2
	require_config_value CONFIG_WARP_VERSION 2
	require_config_value CONFIG_WARP_CHIPSET '"mt7981"'
	require_symbol CONFIG_PACKAGE_luci-app-mtwifi-cfg
	require_symbol CONFIG_PACKAGE_mtwifi-cfg
	require_symbol CONFIG_PACKAGE_datconf
	require_symbol CONFIG_PACKAGE_datconf-lua
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
