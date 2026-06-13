#!/bin/sh

set -eu

config_name="${1:?config name required}"
config_file="${2:-.config}"

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

require_symbol CONFIG_TARGET_qualcommax
require_symbol CONFIG_TARGET_qualcommax_ipq60xx
require_symbol CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_redmi_ax5
require_symbol CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_redmi_ax5-jdcloud
require_symbol CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01
require_symbol CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_qihoo_360v6
require_symbol CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_zn_m2

require_symbol CONFIG_PACKAGE_kmod-ath11k-ahb
require_symbol CONFIG_PACKAGE_kmod-ath11k-pci
require_any_symbol "IPQ6018 ath11k firmware" \
	CONFIG_PACKAGE_ath11k-firmware-ipq6018-ddwrt \
	CONFIG_PACKAGE_ath11k-firmware-ipq6018

require_symbol CONFIG_PACKAGE_ipq-wifi-redmi_ax5
require_symbol CONFIG_PACKAGE_ipq-wifi-redmi_ax5-jdcloud
require_symbol CONFIG_PACKAGE_ipq-wifi-jdcloud_re-ss-01
require_symbol CONFIG_PACKAGE_ipq-wifi-qihoo_360v6
require_symbol CONFIG_PACKAGE_ipq-wifi-zn_m2

require_symbol CONFIG_PACKAGE_wpad-openssl
require_symbol CONFIG_PACKAGE_kmod-batman-adv
require_symbol CONFIG_PACKAGE_batctl-default
require_symbol CONFIG_PACKAGE_dawn
require_symbol CONFIG_PACKAGE_umdns
require_symbol CONFIG_PACKAGE_jsonfilter
require_symbol CONFIG_PACKAGE_curl
require_symbol CONFIG_PACKAGE_iw
require_symbol CONFIG_PACKAGE_iwinfo

case "$config_name" in
	IPQ60XX-MESH-AC)
		require_symbol CONFIG_PACKAGE_luci
		require_symbol CONFIG_PACKAGE_luci-ssl
		require_symbol CONFIG_PACKAGE_mesh-ac
		require_symbol CONFIG_PACKAGE_mesh-agent
		require_symbol CONFIG_PACKAGE_luci-app-mesh-ac
		require_symbol CONFIG_PACKAGE_luci-app-dawn
		require_symbol CONFIG_PACKAGE_jshn
		;;
	IPQ60XX-MESH-AP)
		require_symbol CONFIG_PACKAGE_mesh-agent
		;;
	*)
		echo "unknown config target: $config_name" >&2
		missing=1
		;;
esac

[ "$missing" = "0" ] || exit 1

echo "required mesh config symbols present for $config_name"
