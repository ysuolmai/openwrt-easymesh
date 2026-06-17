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
	grep -q '^ath11k nss_offload=[01] frame_mode=2$' "$path" || return 0
	rm -f "$path"
}

install_ipq_ap_ath11k_module_override() {
	local modules_dir="$OPENWRT_DIR/files/etc/modules.d"

	mkdir -p "$modules_dir"
	printf '%s\n' 'ath11k nss_offload=0 frame_mode=2' > "$modules_dir/ath11k"
}

inject_sx_7981r128() {
	local dts_src="$ROOT_DIR/target/mediatek/dts/mt7981b-sx-7981r128.dts"
	local dts_dir="$OPENWRT_DIR/target/linux/mediatek/dts"
	local filogic_mk="$OPENWRT_DIR/target/linux/mediatek/image/filogic.mk"
	local board_network="$OPENWRT_DIR/target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
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
                     kmod-sfp kmod-i2c-gpio
  SUPPORTED_DEVICES := sx,7981r128 mediatek,mt7981-spim-snand-7981r128
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 65536k
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
				print "\t\tucidef_set_interfaces_lan_wan \"lan1\" \"lan2\""
				print "\t\t;;"
				done = 1
			}
			{ print }
		' "$board_network" > "$board_network.new"
		mv "$board_network.new" "$board_network"
	fi

	mkdir -p "$(dirname "$uci_defaults")"
	cat > "$uci_defaults" <<'EOF'
#!/bin/sh
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "sx,7981r128" ] || exit 0

uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci commit wireless

uci set network.wan6=interface
uci set network.wan6.device=lan2
uci set network.wan6.proto=dhcpv6
uci set network.wan2=interface
uci set network.wan2.device=eth1
uci set network.wan2.proto=dhcp
uci set network.wan2_6=interface
uci set network.wan2_6.device=eth1
uci set network.wan2_6.proto=dhcpv6
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

uci add system led
uci set system.@led[-1].name='led_lan2'
uci set system.@led[-1].sysfs='green:lan'
uci set system.@led[-1].trigger='netdev'
uci set system.@led[-1].dev='lan2'
uci set system.@led[-1].mode='link tx rx'
uci commit system

exit 0
EOF
	chmod +x "$uci_defaults"
}

clear_prepared_ath11k_module_override

case "$CONFIG_NAME" in
	IPQ60XX-MESH-AC)
		install_shadcn_theme
		;;
	IPQ60XX-MESH-AP)
		install_shadcn_theme
		install_ipq_ap_ath11k_module_override
		;;
	MT7981-MESH-AC)
		install_shadcn_theme
		inject_sx_7981r128
		;;
	MT7981-MESH-AP)
		install_shadcn_theme
		inject_sx_7981r128
		;;
	*)
		echo "unknown config target: $CONFIG_NAME" >&2
		exit 1
		;;
esac

echo "prepared $CONFIG_NAME"
