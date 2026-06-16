#!/bin/sh

ATH11K_NSS_REBOOT_DIR="/etc/easymesh/ath11k"

ath11k_nss_set_module_config() {
	local value="$1"

	[ -f /etc/modules.d/ath11k ] || return 0
	if grep -q 'nss_offload=' /etc/modules.d/ath11k; then
		sed -i "s/nss_offload=[01]/nss_offload=$value/g" /etc/modules.d/ath11k
	else
		sed -i "s/^ath11k\([[:space:]]\|$\)/ath11k nss_offload=$value\1/" /etc/modules.d/ath11k
	fi
}

ath11k_nss_schedule_reboot() {
	local value="$1"
	local reason="$2"
	local pending_apply="${3:-}"
	local marker="$ATH11K_NSS_REBOOT_DIR/rebooted-nss-offload-$value"

	[ "$value" = "0" ] || return 1
	[ -d /sys/module/ath11k ] || return 1

	mkdir -p "$ATH11K_NSS_REBOOT_DIR"
	rm -f "$ATH11K_NSS_REBOOT_DIR/rebooted-nss-offload-1"
	[ ! -f "$marker" ] || return 1
	touch "$marker"

	if [ -n "$pending_apply" ]; then
		mkdir -p "${pending_apply%/*}"
		touch "$pending_apply"
	fi

	logger -t easymesh-ath11k "scheduled reboot for ath11k nss_offload=$value ($reason)"
	(sleep 5; reboot) >/dev/null 2>&1 &
	return 0
}

ath11k_nss_set_offload() {
	local value="$1"
	local reason="${2:-mesh config}"
	local pending_apply="${3:-}"

	ath11k_nss_set_module_config "$value"
	echo "$value" > /sys/module/ath11k/parameters/nss_offload 2>/dev/null || true

	if [ "$value" = "1" ]; then
		mkdir -p "$ATH11K_NSS_REBOOT_DIR"
		rm -f "$ATH11K_NSS_REBOOT_DIR/rebooted-nss-offload-0"
		return 1
	fi

	ath11k_nss_schedule_reboot "$value" "$reason" "$pending_apply"
}
