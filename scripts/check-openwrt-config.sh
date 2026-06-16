#!/bin/sh

set -eu

config_name="${1:?config name required}"
config_file="${2:-.config}"
openwrt_dir="$(cd "$(dirname "$config_file")" && pwd)"
ipq60xx_image_mk="$openwrt_dir/target/linux/qualcommax/image/ipq60xx.mk"
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

require_common_mesh_packages() {
	require_symbol CONFIG_PACKAGE_wpad-openssl
	require_symbol CONFIG_PACKAGE_kmod-batman-adv
	require_symbol CONFIG_PACKAGE_batctl-default
	require_symbol CONFIG_PACKAGE_dawn
	require_symbol CONFIG_PACKAGE_umdns
	require_symbol CONFIG_PACKAGE_jsonfilter
	require_symbol CONFIG_PACKAGE_curl
	require_symbol CONFIG_PACKAGE_iw
	require_symbol CONFIG_PACKAGE_iwinfo
}

require_ipq60xx_target() {
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

	require_file_contains "$ipq60xx_image_mk" "ipq-wifi-redmi_ax5" "redmi_ax5 BDF package"
	require_file_contains "$ipq60xx_image_mk" "ipq-wifi-redmi_ax5-jdcloud" "redmi_ax5-jdcloud BDF package"
	require_file_contains "$ipq60xx_image_mk" "ipq-wifi-jdcloud_re-ss-01" "jdcloud_re-ss-01 BDF package"
	require_file_contains "$ipq60xx_image_mk" "ipq-wifi-qihoo_360v6" "qihoo_360v6 BDF package"
	require_file_contains "$ipq60xx_image_mk" "ipq-wifi-zn_m2" "zn_m2 BDF package"
}

require_mt7981_target() {
	require_symbol CONFIG_TARGET_mediatek
	require_symbol CONFIG_TARGET_mediatek_filogic
	require_symbol CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_sx_7981r128
	require_symbol CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_nokia_ea0326gmp
	require_symbol CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m

	require_symbol CONFIG_PACKAGE_kmod-mt7915e
	require_symbol CONFIG_PACKAGE_kmod-mt7981-firmware
	require_symbol CONFIG_PACKAGE_mt7981-wo-firmware

	require_file_contains "$mt7981_image_mk" "define Device/sx_7981r128" "sx_7981r128 injected device profile"
	require_file_contains "$mt7981_image_mk" "define Device/nokia_ea0326gmp" "nokia_ea0326gmp device profile"
	require_file_contains "$mt7981_image_mk" "define Device/cmcc_rax3000m" "cmcc_rax3000m device profile"
	require_file_contains "$mt7981_image_mk" "kmod-mt7915e" "MT7981 Wi-Fi driver package"
	require_file_contains "$mt7981_image_mk" "kmod-mt7981-firmware" "MT7981 firmware package"
	require_file_contains "$mt7981_image_mk" "mt7981-wo-firmware" "MT7981 WO firmware package"
}

require_ac_packages() {
	require_symbol CONFIG_PACKAGE_luci
	require_symbol CONFIG_PACKAGE_luci-ssl
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
	require_symbol CONFIG_PACKAGE_luci-ssl
	require_symbol CONFIG_PACKAGE_luci-theme-shadcn
	require_symbol CONFIG_PACKAGE_easymesh-agent
}

require_ipq_ap_rootfs_overrides() {
	require_file_exact "$openwrt_dir/files/etc/modules.d/ath11k" \
		"ath11k nss_offload=0 frame_mode=2" \
		"IPQ AP ath11k module parameters"
}

case "$config_name" in
	IPQ60XX-MESH-AC)
		require_ipq60xx_target
		require_common_mesh_packages
		require_ac_packages
		;;
	IPQ60XX-MESH-AP)
		require_ipq60xx_target
		require_common_mesh_packages
		require_ap_packages
		require_ipq_ap_rootfs_overrides
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
