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
	local uci_defaults="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults/98_sx_7981r128_init.sh"

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
                     kmod-sfp kmod-i2c-gpio
  SUPPORTED_DEVICES := sx,7981r128 mediatek,mt7981-spim-snand-7981r128
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k
  UBINIZE_OPTS := -E 5
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sx_7981r128
EOF
	fi

	if [ -f "$board_network" ] && ! grep -q 'sx,7981r128' "$board_network"; then
		awk '
			!done && /^\t\*\)$/ {
				print "\tsx,7981r128)"
				print "\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"eth1\""
				print "\t\t;;"
				done = 1
			}
			{ print }
		' "$board_network" > "$board_network.new"
		mv "$board_network.new" "$board_network"
	fi

	if [ -f "$board_leds" ] && ! grep -q 'sx,7981r128' "$board_leds"; then
		awk '
			!done && /^\t\*\)$/ {
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

uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci commit wireless

. /lib/functions.sh

BRIDGE_SECTION=""
find_bridge_section() {
	local section="$1"
	local name type
	config_get name "$section" name
	config_get type "$section" type
	if [ "$name" = "br-lan" ] && [ "$type" = "bridge" ]; then
		BRIDGE_SECTION="$section"
	fi
}

config_load network
config_foreach find_bridge_section device
LAN_BRIDGE_SECTION="${BRIDGE_SECTION:-br_lan}"
if [ -z "$BRIDGE_SECTION" ]; then
	uci set network.br_lan=device
	uci set network.br_lan.name=br-lan
	uci set network.br_lan.type=bridge
fi
uci del_list "network.$LAN_BRIDGE_SECTION.ports=lan1" >/dev/null 2>&1 || true
uci add_list "network.$LAN_BRIDGE_SECTION.ports=lan1"
uci del_list "network.$LAN_BRIDGE_SECTION.ports=lan2" >/dev/null 2>&1 || true
uci add_list "network.$LAN_BRIDGE_SECTION.ports=lan2"
uci set network.lan=interface
uci set network.lan.device=br-lan

uci set network.wan=interface
uci set network.wan.device=eth1
uci set network.wan.proto=dhcp
uci set network.wan6=interface
uci set network.wan6.device=@wan
uci set network.wan6.proto=dhcpv6
uci delete network.wan2 >/dev/null 2>&1 || true
uci delete network.wan2_6 >/dev/null 2>&1 || true
uci commit network

lan_zone_idx=""
wan_zone_idx=""
i=0
while uci get "firewall.@zone[$i]" >/dev/null 2>&1; do
	case "$(uci get firewall.@zone[$i].name 2>/dev/null)" in
		lan) lan_zone_idx=$i ;;
		wan) wan_zone_idx=$i ;;
	esac
	i=$((i + 1))
done
if [ -n "$lan_zone_idx" ]; then
	uci del_list firewall.@zone[$lan_zone_idx].network=wan >/dev/null 2>&1 || true
	uci del_list firewall.@zone[$lan_zone_idx].network=wan6 >/dev/null 2>&1 || true
	uci del_list firewall.@zone[$lan_zone_idx].network=wan2 >/dev/null 2>&1 || true
	uci del_list firewall.@zone[$lan_zone_idx].network=wan2_6 >/dev/null 2>&1 || true
	uci add_list firewall.@zone[$lan_zone_idx].network=lan
	uci set firewall.@zone[$lan_zone_idx].input=ACCEPT
	uci set firewall.@zone[$lan_zone_idx].output=ACCEPT
	uci set firewall.@zone[$lan_zone_idx].forward=ACCEPT
fi
if [ -n "$wan_zone_idx" ]; then
	uci del_list firewall.@zone[$wan_zone_idx].network=wan2 >/dev/null 2>&1 || true
	uci del_list firewall.@zone[$wan_zone_idx].network=wan2_6 >/dev/null 2>&1 || true
	uci add_list firewall.@zone[$wan_zone_idx].network=wan
	uci add_list firewall.@zone[$wan_zone_idx].network=wan6
fi
uci commit firewall

/etc/init.d/network restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/firewall restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/dropbear restart >/dev/null 2>&1 || true

exit 0
EOF
	chmod +x "$uci_defaults"
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
