#!/bin/sh

set -eu

CONFIG_NAME="${1:-IPQ60XX-MESH-AC}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OPENWRT_DIR="${OPENWRT_DIR:-$(pwd)}"
CONFIG_FILE="$ROOT_DIR/configs/$CONFIG_NAME.txt"

[ -f "$CONFIG_FILE" ] || {
	echo "missing config: $CONFIG_FILE" >&2
	exit 1
}

[ -d "$OPENWRT_DIR/package" ] || {
	echo "OPENWRT_DIR does not look like OpenWrt: $OPENWRT_DIR" >&2
	exit 1
}

mkdir -p "$OPENWRT_DIR/package/openwrt-easymesh"
cp -R "$ROOT_DIR/package/." "$OPENWRT_DIR/package/openwrt-easymesh/"

cat "$CONFIG_FILE" >> "$OPENWRT_DIR/.config"

install_shadcn_theme() {
	[ "${SKIP_SHADCN_CLONE:-0}" = "1" ] && return 0
	local dst="$OPENWRT_DIR/package/luci-theme-shadcn"

	if [ -d "$dst" ]; then
		rm -rf "$dst"
	fi
	git clone --depth=1 --single-branch --branch main \
		https://github.com/ysuolmai/luci-theme-shadcn.git "$dst"

	find "$OPENWRT_DIR/feeds/luci/collections" -type f -name Makefile \
		-exec sed -i 's/luci-theme-bootstrap/luci-theme-shadcn/g' {} +
}

clear_prepared_ath11k_module_override() {
	local path="$OPENWRT_DIR/files/etc/modules.d/ath11k"

	[ -f "$path" ] || return 0
	grep -Eq '^ath11k nss_offload=[01]( frame_mode=[0-9]+)?$' "$path" || return 0
	rm -f "$path"
}

install_ipq_ath11k_module_override() {
	local value="$1"
	local modules_dir="$OPENWRT_DIR/files/etc/modules.d"

	mkdir -p "$modules_dir"
	printf 'ath11k nss_offload=%s frame_mode=0\n' "$value" > "$modules_dir/ath11k"
}


inject_sx_7981r128() {
	local dts_src="$ROOT_DIR/target/mediatek/dts/mt7981b-sx-7981r128.dts"
	local dts_dir="$OPENWRT_DIR/target/linux/mediatek/dts"
	local filogic_mk="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
	local board_network="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
	local board_leds="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
	local platform_sh="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
	local uci_defaults="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults/98_sx_7981r128_init.sh"

	[ -f "$dts_src" ] || {
		echo "missing SX 7981R128 DTS: $dts_src" >&2
		exit 1
	}
	[ -d "$dts_dir" ] || {
		echo "missing MediaTek DTS directory: $dts_dir" >&2
		exit 1
	}
	[ -f "$filogic_mk" ] || {
		echo "missing MediaTek filogic image file: $filogic_mk" >&2
		exit 1
	}

	cp "$dts_src" "$dts_dir/"

	if ! grep -q '^define Device/sx_7981r128' "$filogic_mk"; then
		cat >> "$filogic_mk" <<'EOF'

define Device/sx_7981r128
  DEVICE_VENDOR := SX
  DEVICE_MODEL := 7981R128
  DEVICE_DTS := mt7981b-sx-7981r128
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 \
                     kmod-sfp kmod-i2c-gpio automount f2fsck mkf2fs
  SUPPORTED_DEVICES := sx,7981r128 mediatek,mt7981-spim-snand-7981r128 mediatek,zhao-7981r128-d
  KERNEL_IN_UBI := 1
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  UBINIZE_OPTS := -E 5
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sx_7981r128
EOF
	fi

	if [ -f "$board_network" ] && ! grep -q 'sx,7981r128' "$board_network"; then
		awk '
			/^mediatek_setup_interfaces\(\)$/ { in_interfaces = 1; in_macs = 0 }
			/^mediatek_setup_macs\(\)$/ { in_interfaces = 0; in_macs = 1 }
			in_interfaces && !done_interfaces && /^\t\*\)$/ {
				print "\tsx,7981r128)"
				print "\t\tucidef_set_interfaces_lan_wan \"lan1\" \"lan2\""
				print "\t\t;;"
				done_interfaces = 1
			}
			in_macs && !done_macs && /^\tesac$/ {
				print "\tsx,7981r128)"
				print "\t\tlan_mac=$(mtd_get_mac_binary factory 0x04)"
				print "\t\t[ -n \"$lan_mac\" ] || lan_mac=$(mtd_get_mac_binary Factory 0x04)"
				print "\t\t[ -n \"$lan_mac\" ] && wan_mac=$(macaddr_add \"$lan_mac\" 1)"
				print "\t\t[ -n \"$lan_mac\" ] && label_mac=$lan_mac"
				print "\t\t;;"
				done_macs = 1
			}
			{ print }
		' "$board_network" > "$board_network.new"
		mv "$board_network.new" "$board_network"
	fi

	if [ -f "$board_leds" ] && ! grep -q 'sx,7981r128' "$board_leds"; then
		awk '
			!done && /^esac$/ {
				print "\tsx,7981r128)"
				print "\t\tucidef_set_led_netdev \"lan2\" \"LAN2\" \"green:lan\" \"lan2\" \"link tx rx\""
				print "\t\tucidef_set_led_netdev \"sfp\" \"SFP\" \"green:wan\" \"eth1\" \"link tx rx\""
				print "\t\tucidef_set_led_netdev \"wlan2g\" \"WIFI2G\" \"green:wlan-2ghz\" \"phy0-ap0\" \"link tx rx\""
				print "\t\tucidef_set_led_netdev \"wlan5g\" \"WIFI5G\" \"green:wlan-5ghz\" \"phy1-ap0\" \"link tx rx\""
				print "\t\t;;"
				done = 1
			}
			{ print }
		' "$board_leds" > "$board_leds.new"
		mv "$board_leds.new" "$board_leds"
	fi

	mkdir -p "$(dirname "$uci_defaults")"
	cat > "$uci_defaults" <<'EOF'
#!/bin/sh
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "sx,7981r128" ] || exit 0

. /lib/functions.sh
. /lib/functions/system.sh

uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci commit wireless

uci set network.wan.metric=10
uci set network.wan6=interface
uci set network.wan6.device=lan2
uci set network.wan6.proto=dhcpv6
uci set network.wan6.metric=10
uci set network.wan2=interface
uci set network.wan2.device=eth1
uci set network.wan2.proto=dhcp
uci set network.wan2.metric=20
uci set network.wan2_6=interface
uci set network.wan2_6.device=eth1
uci set network.wan2_6.proto=dhcpv6
uci set network.wan2_6.metric=20
base_mac=$(mtd_get_mac_binary factory 0x04 2>/dev/null)
[ -n "$base_mac" ] || base_mac=$(mtd_get_mac_binary Factory 0x04 2>/dev/null)
if [ -n "$base_mac" ]; then
	uci set network.wan2.macaddr="$(macaddr_add "$base_mac" 2)"
fi
uci commit network

wan_zone_idx=""
i=0
while uci get "firewall.@zone[$i]" >/dev/null 2>&1; do
	if [ "$(uci get firewall.@zone[$i].name 2>/dev/null)" = "wan" ]; then
		wan_zone_idx=$i
		break
	fi
	i=$((i + 1))
done
if [ -n "$wan_zone_idx" ]; then
	uci add_list firewall.@zone[$wan_zone_idx].network=wan2
	uci add_list firewall.@zone[$wan_zone_idx].network=wan2_6
	uci commit firewall
fi

exit 0
EOF
	chmod +x "$uci_defaults"

	if [ -f "$platform_sh" ] && ! grep -q 'sx,7981r128' "$platform_sh"; then
		awk '
			/^platform_do_upgrade\(\) \{/ { in_upgrade = 1 }
			in_upgrade && !upgrade_done && /^\t(jiorouter,ax6000-jidu6101|ruijie,rg-x30e-pro)\)$/ {
				print "\tsx,7981r128|\\"
				upgrade_done = 1
			}
			/^platform_check_image\(\) \{/ { in_upgrade = 0; in_check = 1 }
			in_check && !check_done && /^\tnradio,c8-668gl\)$/ {
				print "\tsx,7981r128|\\"
				check_done = 1
			}
			{ print }
		' "$platform_sh" > "$platform_sh.new"
		mv "$platform_sh.new" "$platform_sh"
	fi
}

case "$CONFIG_NAME" in
	IPQ60XX-MESH-AC)
		install_shadcn_theme
		install_ipq_ath11k_module_override 0
		;;
	IPQ60XX-MESH-AP)
		install_shadcn_theme
		install_ipq_ath11k_module_override 0
		;;
	MT7981-MESH-AC)
		install_shadcn_theme
		clear_prepared_ath11k_module_override
		inject_sx_7981r128
		;;
	MT7981-MESH-AP)
		install_shadcn_theme
		clear_prepared_ath11k_module_override
		inject_sx_7981r128
		;;
	*)
		echo "unknown config target: $CONFIG_NAME" >&2
		exit 1
		;;
esac

echo "prepared $CONFIG_NAME"
