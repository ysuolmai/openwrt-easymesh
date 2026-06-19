#!/bin/sh

ATH11K_NSS_MODULE_CONFIG="/etc/modules.d/ath11k"
ATH11K_NSS_REBOOT_DIR="/etc/easymesh/ath11k"
ATH11K_NSS_FRAME_MODE="0"

ath11k_nss_get_module_config() {
	[ -f "$ATH11K_NSS_MODULE_CONFIG" ] || return 1
	sed -n 's/.*nss_offload=\([01]\).*/\1/p' "$ATH11K_NSS_MODULE_CONFIG" | head -n 1
}

ath11k_nss_set_module_config() {
	local value="$1"

	if [ ! -f "$ATH11K_NSS_MODULE_CONFIG" ] && [ ! -d /sys/module/ath11k ]; then
		return 1
	fi

	mkdir -p "${ATH11K_NSS_MODULE_CONFIG%/*}"
	if [ ! -f "$ATH11K_NSS_MODULE_CONFIG" ]; then
		printf 'ath11k nss_offload=%s frame_mode=%s\n' "$value" "$ATH11K_NSS_FRAME_MODE" > "$ATH11K_NSS_MODULE_CONFIG"
		return 0
	fi

	if grep -q 'nss_offload=' "$ATH11K_NSS_MODULE_CONFIG"; then
		sed -i "s/nss_offload=[01]/nss_offload=$value/g" "$ATH11K_NSS_MODULE_CONFIG"
	else
		sed -i "s/^ath11k\([[:space:]]\|$\)/ath11k nss_offload=$value\1/" "$ATH11K_NSS_MODULE_CONFIG"
	fi

	if grep -q 'frame_mode=' "$ATH11K_NSS_MODULE_CONFIG"; then
		sed -i "s/frame_mode=[^[:space:]]*/frame_mode=$ATH11K_NSS_FRAME_MODE/g" "$ATH11K_NSS_MODULE_CONFIG"
	else
		sed -i "/^ath11k/ s/$/ frame_mode=$ATH11K_NSS_FRAME_MODE/" "$ATH11K_NSS_MODULE_CONFIG"
	fi
}

ath11k_nss_runtime_value() {
	local path="/sys/module/ath11k/parameters/nss_offload"

	[ -r "$path" ] || return 1
	cat "$path" 2>/dev/null
}

ath11k_nss_runtime_frame_mode() {
	local path="/sys/module/ath11k/parameters/frame_mode"

	[ -r "$path" ] || return 1
	cat "$path" 2>/dev/null
}

ath11k_nss_set_runtime_frame_mode() {
	local path="/sys/module/ath11k/parameters/frame_mode"

	[ -w "$path" ] || return 1
	echo "$ATH11K_NSS_FRAME_MODE" > "$path" 2>/dev/null
}

ath11k_nss_schedule_reboot() {
	local value="$1"
	local reason="$2"
	local pending_apply="${3:-}"
	local marker="$ATH11K_NSS_REBOOT_DIR/rebooted-nss-offload-$value"

	[ -d /sys/module/ath11k ] || return 1

	mkdir -p "$ATH11K_NSS_REBOOT_DIR"
	if [ "$value" = "1" ]; then
		rm -f "$ATH11K_NSS_REBOOT_DIR/rebooted-nss-offload-0"
	else
		rm -f "$ATH11K_NSS_REBOOT_DIR/rebooted-nss-offload-1"
	fi
	[ ! -f "$marker" ] || return 1
	touch "$marker"

	if [ -n "$pending_apply" ]; then
		mkdir -p "${pending_apply%/*}"
		touch "$pending_apply"
	fi

	logger -t easymesh-ath11k "scheduled reboot for ath11k nss_offload=$value frame_mode=$ATH11K_NSS_FRAME_MODE ($reason)"
	(sleep 5; reboot) >/dev/null 2>&1 &
	return 0
}

ath11k_nss_set_offload() {
	local value="$1"
	local reason="${2:-mesh config}"
	local pending_apply="${3:-}"
	local frame_runtime
	local runtime

	ath11k_nss_set_module_config "$value" || return 1

	if [ ! -d /sys/module/ath11k ]; then
		return 1
	fi

	echo "$value" > /sys/module/ath11k/parameters/nss_offload 2>/dev/null || true
	ath11k_nss_set_runtime_frame_mode || true
	runtime="$(ath11k_nss_runtime_value 2>/dev/null || true)"
	frame_runtime="$(ath11k_nss_runtime_frame_mode 2>/dev/null || true)"
	[ "$runtime" = "$value" ] && [ "$frame_runtime" = "$ATH11K_NSS_FRAME_MODE" ] && return 1

	ath11k_nss_schedule_reboot "$value" "$reason" "$pending_apply"
}
