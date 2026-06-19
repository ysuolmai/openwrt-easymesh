#!/bin/sh

set -eu

config_name="${1:?config name required}"
config_file="${2:-.config}"
openwrt_dir="$(cd "$(dirname "$config_file")" && pwd)"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
expected_config="$repo_dir/configs/$config_name.txt"
mt7981_image_mk="$openwrt_dir/target/linux/mediatek/image/filogic.mk"

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

require_any_symbol() {
	local label="$1"
	shift
	local symbol
	for symbol in "$@"; do
		if grep -q "^${symbol}=y$" "$config_file"; then
			return 0
		fi
	done
	echo "missing required config group: ${label}" >&2
	printf '  accepted:' >&2
	for symbol in "$@"; do
		printf ' %s=y' "$symbol" >&2
	done
	printf '\n' >&2
	missing=1
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

require_file_exact() {
	local file="$1"
	local expected="$2"
	local label="$3"

	if [ ! -f "$file" ]; then
		echo "missing required file for ${label}: ${file}" >&2
		missing=1
		return
	fi
	if [ "$(cat "$file")" != "$expected" ]; then
		echo "unexpected file content for ${label}: ${file}" >&2
		missing=1
	fi
}

require_ipq_ath11k_module_override() {
	require_file_exact "$openwrt_dir/files/etc/modules.d/ath11k" \
		"ath11k nss_offload=0 frame_mode=0" \
		"IPQ ath11k default NSS offload state"
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

require_luci_ssl() {
	case "$config_name" in
		IPQ60XX-*) require_symbol CONFIG_PACKAGE_luci-ssl-openssl ;;
		*) require_symbol CONFIG_PACKAGE_luci-ssl ;;
	esac
}

require_ipq60xx_target() {
	require_symbol CONFIG_TARGET_qualcommax
	require_symbol CONFIG_TARGET_qualcommax_ipq60xx
	require_expected_device_symbols \
		CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_ \
		"OpenWRT-CI IPQ60XX device list"

	require_symbol CONFIG_PACKAGE_kmod-ath11k-ahb
	require_symbol CONFIG_PACKAGE_kmod-ath11k-pci
	require_any_symbol "IPQ6018 ath11k firmware" \
		CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt \
		CONFIG_PACKAGE_ath11k-firmware-ipq6018
}

require_mt7981_target() {
	require_symbol CONFIG_TARGET_mediatek
	require_symbol CONFIG_TARGET_mediatek_filogic
	require_expected_device_symbols \
		CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_ \
		"OpenWRT-CI MEDIATEK device list" \
		"$mt7981_image_mk"

	require_symbol CONFIG_PACKAGE_kmod-mt7915e
	require_symbol CONFIG_PACKAGE_kmod-mt7981-firmware
	require_symbol CONFIG_PACKAGE_mt7981-wo-firmware
	require_symbol CONFIG_PACKAGE_kmod-cryptodev
	require_symbol CONFIG_PACKAGE_kmod-tls

	require_file_contains "$mt7981_image_mk" "define Device/sx_7981r128" "sx_7981r128 injected device profile"
	require_file_contains "$mt7981_image_mk" "kmod-mt7915e" "MT7981 Wi-Fi driver package"
	require_file_contains "$mt7981_image_mk" "kmod-mt7981-firmware" "MT7981 firmware package"
	require_file_contains "$mt7981_image_mk" "mt7981-wo-firmware" "MT7981 WO firmware package"
}

require_ac_packages() {
	require_symbol CONFIG_PACKAGE_luci
	require_luci_ssl
	require_symbol CONFIG_PACKAGE_easymesh-controller
	require_symbol CONFIG_PACKAGE_easymesh-local-member
	require_symbol CONFIG_PACKAGE_easymesh-agent
	require_symbol CONFIG_PACKAGE_luci-app-easymesh
	require_symbol CONFIG_PACKAGE_luci-theme-shadcn
	require_symbol CONFIG_PACKAGE_luci-app-dawn
	require_symbol CONFIG_PACKAGE_jshn
	require_symbol CONFIG_PACKAGE_umdns
}

require_ap_packages() {
	require_symbol CONFIG_PACKAGE_luci
	require_luci_ssl
	require_symbol CONFIG_PACKAGE_luci-theme-shadcn
	require_symbol CONFIG_PACKAGE_easymesh-agent
}

case "$config_name" in
	IPQ60XX-MESH-AC)
		require_ipq60xx_target
		require_common_mesh_packages
		require_ac_packages
		require_ipq_ath11k_module_override
		;;
	IPQ60XX-MESH-AP)
		require_ipq60xx_target
		require_common_mesh_packages
		require_ap_packages
		require_ipq_ath11k_module_override
		;;
	MT7981-MESH-AC)
		require_mt7981_target
		require_common_mesh_packages
		require_ac_packages
		;;
	MT7981-MESH-AP)
		require_mt7981_target
		require_common_mesh_packages
		require_ap_packages
		;;
	*)
		echo "unknown config target: $config_name" >&2
		missing=1
		;;
esac

[ "$missing" = "0" ] || exit 1

echo "required mesh config symbols present for $config_name"
