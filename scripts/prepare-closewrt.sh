#!/bin/sh

set -eu

CONFIG_NAME="${1:-CLOSEWRT-MT7981-MESH-AC}"
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

inject_sx_7981r128() {
	local broken_uboot_patch="$OPENWRT_DIR/package/boot/uboot-mediatek/patches/472-add-globitel-bt-r320.patch"
	local dts_src="$ROOT_DIR/target/mediatek/closewrt/dts/mt7981b-sx-7981r128.dts"
	local patch_src_dir="$ROOT_DIR/target/mediatek/closewrt/patches-6.6"
	local patch_dst_dir="$OPENWRT_DIR/target/linux/mediatek/patches-6.6"
	local dts_dir="$OPENWRT_DIR/target/linux/mediatek/dts"
	local filogic_mk="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
	local board_network="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
	local board_leds="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/01_leds"
	local platform_sh="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh"
	local uboot_envtools="$OPENWRT_DIR/package/boot/uboot-tools/uboot-envtools/files/mediatek_filogic"
	local smp_sh="$OPENWRT_DIR/package/mtk/applications/mtk-smp/files/smp.sh"
	local uci_defaults="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults/98_sx_7981r128_init.sh"
	local led_defaults="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults/99_sx_7981r128_leds.sh"

	if [ -f "$broken_uboot_patch" ]; then
		rm -f "$broken_uboot_patch"
	fi

	[ -f "$dts_src" ] || {
		echo "missing SX 7981R128 CloseWRT DTS: $dts_src" >&2
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
	if [ -d "$patch_src_dir" ] && [ -d "$patch_dst_dir" ]; then
		find "$patch_src_dir" -maxdepth 1 -type f -name '*.patch' -exec cp -f {} "$patch_dst_dir"/ \;
	fi

	if ! grep -q '^define Device/sx_7981r128' "$filogic_mk"; then
		cat >> "$filogic_mk" <<'EOF'

define Device/sx_7981r128
  DEVICE_VENDOR := SX
  DEVICE_MODEL := 7981R128
  DEVICE_DTS := mt7981b-sx-7981r128
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 \
                     kmod-sfp kmod-i2c-gpio uboot-envtools
  SUPPORTED_DEVICES := sx,7981r128 mediatek,mt7981-spim-snand-7981r128 \
                       mediatek,zhao-7981r128-d zhao,7981r128
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
			!done && (/^\t\*\)$/ || /^esac$/) {
				print "\tsx,7981r128)"
				print "\t\tucidef_set_led_netdev \"lan\" \"LAN\" \"green:lan\" \"lan2\""
				print "\t\tucidef_set_led_netdev \"sfp\" \"SFP\" \"green:wan\" \"eth1\" \"link\""
				print "\t\tucidef_set_led_netdev \"wifi5g\" \"WIFI5G\" \"green:wlan-5ghz\" \"rax0\" \"tx rx\""
				print "\t\tucidef_set_led_netdev \"wifi2g\" \"WIFI2G\" \"green:wlan-2ghz\" \"ra0\" \"tx rx\""
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
			/^platform_do_upgrade\(\)/ { in_upgrade = 1; in_check = 0 }
			/^platform_check_image\(\)/ { in_upgrade = 0; in_check = 1 }
			in_upgrade && !done_upgrade && /^\t\*\)$/ {
				print "\tsx,7981r128)"
				print "\t\tCI_UBIPART=\"ubi\""
				print "\t\tnand_do_upgrade \"$1\""
				print "\t\t;;"
				print
				done_upgrade = 1
				next
			}
			in_check && !done_check && /\tnradio,c8-668gl\)/ {
				sub(/\)$/, "|\\")
				print
				print "\tsx,7981r128)"
				done_check = 1
				next
			}
			{ print }
		' "$platform_sh" > "$platform_sh.new"
		mv "$platform_sh.new" "$platform_sh"
	fi

	if [ -f "$uboot_envtools" ] && ! grep -q 'sx,7981r128' "$uboot_envtools"; then
		awk '
			!done && /^[[:space:]]*zhao,7981r128\)$/ {
				print "\tsx,7981r128|\\"
				done = 1
			}
			!done && /^[[:space:]]*zbtlink,zbt-z8103ax\)$/ {
				sub(/\)$/, "|\\")
				print
				print "\tsx,7981r128)"
				done = 1
				next
			}
			{ print }
		' "$uboot_envtools" > "$uboot_envtools.new"
		mv "$uboot_envtools.new" "$uboot_envtools"
	fi

	if [ -f "$smp_sh" ] && ! grep -q 'sx,7981r128' "$smp_sh"; then
		awk '
			!done && /^\t\*7981\*\)$/ {
				print "\tzhao,7981r128 |\\"
				print "\tsx,7981r128 |\\"
				done = 1
			}
			{ print }
		' "$smp_sh" > "$smp_sh.new"
		mv "$smp_sh.new" "$smp_sh"
	fi

	mkdir -p "$(dirname "$led_defaults")"
	cat > "$led_defaults" <<'EOF'
#!/bin/sh
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "sx,7981r128" ] || exit 0

pick_led() {
	for led in "$@"; do
		[ -e "/sys/class/leds/$led" ] && {
			printf '%s' "$led"
			return
		}
	done
	printf '%s' "$1"
}

led_lan_sysfs="$(pick_led green:lan LAN)"
led_sfp_sysfs="$(pick_led green:wan SFP)"
led_wifi5g_sysfs="$(pick_led green:wlan-5ghz WIFI5G)"
led_wifi2g_sysfs="$(pick_led green:wlan-2ghz WIFI2G)"

while true; do
	old_led="$(uci show system 2>/dev/null | sed -n "s/^\(system\.[^=]*\)\.name='led_lan2'$/\1/p" | head -n1)"
	[ -n "$old_led" ] || break
	uci -q delete "$old_led"
done
uci -q delete system.led_lan2
uci -q delete system.led_lan
uci -q delete system.led_sfp
uci -q delete system.led_wifi5g
uci -q delete system.led_wifi2g

uci set system.led_lan=led
uci set system.led_lan.name='LAN'
uci set system.led_lan.sysfs="$led_lan_sysfs"
uci set system.led_lan.trigger='netdev'
uci set system.led_lan.dev='lan2'
uci set system.led_lan.mode='link tx rx'

uci set system.led_sfp=led
uci set system.led_sfp.name='SFP'
uci set system.led_sfp.sysfs="$led_sfp_sysfs"
uci set system.led_sfp.trigger='netdev'
uci set system.led_sfp.dev='eth1'
uci set system.led_sfp.mode='link'

uci set system.led_wifi5g=led
uci set system.led_wifi5g.name='WIFI5G'
uci set system.led_wifi5g.sysfs="$led_wifi5g_sysfs"
uci set system.led_wifi5g.trigger='netdev'
uci set system.led_wifi5g.dev='rax0'
uci set system.led_wifi5g.mode='tx rx'

uci set system.led_wifi2g=led
uci set system.led_wifi2g.name='WIFI2G'
uci set system.led_wifi2g.sysfs="$led_wifi2g_sysfs"
uci set system.led_wifi2g.trigger='netdev'
uci set system.led_wifi2g.dev='ra0'
uci set system.led_wifi2g.mode='tx rx'

uci commit system
exit 0
EOF
	chmod +x "$led_defaults"
}

case "$CONFIG_NAME" in
	CLOSEWRT-MT7981-MESH-AC)
		install_shadcn_theme
		inject_sx_7981r128
		;;
	CLOSEWRT-MT7981-MESH-AP)
		install_shadcn_theme
		inject_sx_7981r128
		;;
	*)
		echo "unknown config target: $CONFIG_NAME" >&2
		exit 1
		;;
esac

echo "prepared $CONFIG_NAME"
