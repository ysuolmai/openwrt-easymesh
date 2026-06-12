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

mkdir -p "$OPENWRT_DIR/package/openwrt-ipq-mesh"
cp -R "$ROOT_DIR/package/." "$OPENWRT_DIR/package/openwrt-ipq-mesh/"

cat "$CONFIG_FILE" >> "$OPENWRT_DIR/.config"

sed -i "/^CONFIG_TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_/{
	/\\(redmi_ax5\\|redmi_ax5-jdcloud\\|jdcloud_re-ss-01\\|qihoo_360v6\\)=y$/!d
}" "$OPENWRT_DIR/.config"

echo "prepared $CONFIG_NAME"
