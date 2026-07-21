#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck disable=SC3043  # 'local' is supported by busybox ash (OpenWrt convention)
# shellcheck disable=SC1090,SC2153  # the pending state file is sourced at runtime
# shellcheck disable=SC2119,SC2120  # do_confirm's token argument is optional by design
#
# sysupgrade-confirm — confirmed sysupgrade for dual-firmware OpenWrt devices.
#
# The stock bootloader countdown (layer 1) only catches boots that never reach
# userspace. This tool adds layer 2: after a sysupgrade, the new firmware must
# be explicitly confirmed (CLI, ubus/browser token, or optional auto-checks)
# within a deadline, or the device flips back to the previous firmware
# partition and reboots. The stock bootcount/resetbc mechanism is left
# completely untouched — the two layers are independent.
#
# Usage:
#   sysupgrade-confirm            confirm the running firmware (admin path)
#   sysupgrade-confirm status     show pending state (--json for machines)
#   sysupgrade-confirm arm        arm before a flash (called by the owut hook)
#   sysupgrade-confirm revert     flip boot partition and reboot NOW
#
# State: /etc/sysupgrade-confirm/pending (shell-sourceable; rides the
# sysupgrade config backup so it is present on first boot of the new fw).

STATE_DIR="/etc/sysupgrade-confirm"
PENDING="$STATE_DIR/pending"
BOARDS_DIR="/usr/share/sysupgrade-confirm/boards"

log() { logger -t sysupgrade-confirm "$1"; echo "sysupgrade-confirm: $1" >&2; }

uci_opt() { uci -q get "sysupgrade-confirm.main.$1" || echo "$2"; }

# ---- board table (luci-app-advanced-reboot device JSON format) --------------

board_file() {
	local board bf b
	board=$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name')
	[ -n "$board" ] || return 1
	for bf in "$BOARDS_DIR"/*.json; do
		[ -f "$bf" ] || continue
		for b in $(jsonfilter -i "$bf" -e '@.device.board[*]'); do
			[ "$b" = "$board" ] && { echo "$bf"; return 0; }
		done
	done
	return 1
}

bt_param()   { jsonfilter -i "$1" -e '@.commands.params[0]'; }
bt_get_cmd() { jsonfilter -i "$1" -e '@.commands.get'; }
bt_set_cmd() { jsonfilter -i "$1" -e '@.commands.set'; }

current_value() { # <board_file>
	"$(bt_get_cmd "$1")" -n "$(bt_param "$1")" 2>/dev/null
}

other_value() { # <board_file> <current_value>
	local v
	for v in $(jsonfilter -i "$1" -e '@.partitions[*].param_values[0]'); do
		[ "$v" != "$2" ] && { echo "$v"; return 0; }
	done
	return 1
}

set_value() { # <board_file> <value>
	"$(bt_set_cmd "$1")" "$(bt_param "$1")" "$2"
}

# ---- commands ---------------------------------------------------------------

do_arm() {
	local bf cur deadline token
	bf=$(board_file) || { log "arm FAILED: board not in $BOARDS_DIR — refusing (aborts flash)"; exit 1; }
	cur=$(current_value "$bf")
	[ -n "$cur" ] || { log "arm FAILED: cannot read $(bt_param "$bf") — refusing (aborts flash)"; exit 1; }
	other_value "$bf" "$cur" >/dev/null || { log "arm FAILED: no alternate partition value in board table"; exit 1; }
	deadline=$(uci_opt deadline 600)
	token=$(head -c 16 /dev/urandom | hexdump -v -e '1/1 "%02x"')
	[ -n "$token" ] || { log "arm FAILED: token generation"; exit 1; }
	mkdir -p "$STATE_DIR" || exit 1
	cat > "$PENDING" <<-EOF || { log "arm FAILED: cannot write $PENDING"; exit 1; }
		ARMED_FROM_PART='$cur'
		DEADLINE='$deadline'
		TOKEN='$token'
		ARMED_DATE='$(date -Iseconds 2>/dev/null || date)'
	EOF
	chmod 600 "$PENDING"
	sync
	log "ARMED: on partition value $cur, deadline ${deadline}s after next boot"
	echo "CONFIRM-TOKEN: $token"
	exit 0
}

do_confirm() { # [token]  — empty token = trusted local caller (CLI over SSH)
	[ -f "$PENDING" ] || { echo "nothing pending"; exit 0; }
	if [ -n "$1" ]; then
		. "$PENDING"
		[ "$1" = "$TOKEN" ] || { log "confirm DENIED: bad token"; exit 1; }
	fi
	rm -f "$PENDING"
	sync
	log "CONFIRMED — running firmware committed, revert timer disarmed"
	exit 0
}

do_status() { # [--json]
	local pending=0 remaining=0 up bf cur
	up=$(cut -d. -f1 /proc/uptime)
	bf=$(board_file) && cur=$(current_value "$bf") || cur=""
	if [ -f "$PENDING" ]; then
		. "$PENDING"
		pending=1
		remaining=$((DEADLINE - up))
		[ "$remaining" -lt 0 ] && remaining=0
	fi
	if [ "$1" = "--json" ]; then
		printf '{"pending":%s,"boot_part":"%s","armed_from":"%s","deadline":%s,"uptime":%s,"remaining":%s}\n' \
			"$pending" "$cur" "${ARMED_FROM_PART:-}" "${DEADLINE:-0}" "$up" "$remaining"
	else
		if [ "$pending" = 1 ]; then
			echo "PENDING: unconfirmed firmware (booted from partition value $cur, was $ARMED_FROM_PART)"
			echo "  deadline ${DEADLINE}s after boot — ${remaining}s remaining"
			echo "  confirm with: sysupgrade-confirm"
		else
			echo "confirmed / nothing pending (partition value ${cur:-unknown})"
		fi
	fi
	exit 0
}

do_revert() {
	local bf cur target
	bf=$(board_file) || { log "revert FAILED: unsupported board"; exit 1; }
	cur=$(current_value "$bf")
	if [ -f "$PENDING" ]; then
		. "$PENDING"
		target="$ARMED_FROM_PART"
		rm -f "$PENDING"
	else
		target=$(other_value "$bf" "$cur") || { log "revert FAILED: no alternate"; exit 1; }
	fi
	log "REVERT: partition value $cur -> $target, rebooting"
	set_value "$bf" "$target" || { log "revert FAILED: $(bt_set_cmd "$bf")"; exit 1; }
	sync
	reboot
}

# ---- auto-checks (optional confirm path, uci-configured) --------------------

run_checks() { # returns 0 if all enabled checks pass
	local gw host
	if [ "$(uci_opt check_gateway 1)" = "1" ]; then
		gw=$(ip -4 route show default | sed -n 's/.*via \([0-9.]*\).*/\1/p' | head -1)
		[ -n "$gw" ] || return 1
		ping -c1 -W2 "$gw" >/dev/null 2>&1 || return 1
	fi
	if [ "$(uci_opt check_wan 0)" = "1" ]; then
		host=$(uci_opt check_wan_host "1.1.1.1")
		ping -c1 -W3 "$host" >/dev/null 2>&1 || return 1
	fi
	return 0
}

# ---- daemon (procd, started by /etc/init.d/sysupgrade-confirm) --------------

do_daemon() {
	local bf cur up interval passes needed
	[ -f "$PENDING" ] || exit 0
	. "$PENDING"
	bf=$(board_file) || { log "daemon: unsupported board, clearing pending"; rm -f "$PENDING"; exit 0; }
	cur=$(current_value "$bf")
	if [ "$cur" = "$ARMED_FROM_PART" ]; then
		# We booted the OLD firmware (layer-1 bootloader revert, manual switch,
		# or the flash never happened). Nothing to guard.
		log "daemon: running the pre-flash partition ($cur) — clearing pending"
		rm -f "$PENDING"
		exit 0
	fi
	log "daemon: guarding unconfirmed firmware — revert in ${DEADLINE}s (from boot) unless confirmed"
	interval=$(uci_opt check_interval 10)
	needed=$(uci_opt check_consecutive 3)
	passes=0
	while :; do
		[ -f "$PENDING" ] || { log "daemon: confirmed, exiting"; exit 0; }
		up=$(cut -d. -f1 /proc/uptime)
		if [ "$up" -ge "$DEADLINE" ]; then
			log "daemon: deadline expired unconfirmed"
			do_revert
			exit 0   # not reached
		fi
		if [ "$(uci_opt auto_confirm 0)" = "1" ]; then
			if run_checks; then
				passes=$((passes + 1))
				if [ "$passes" -ge "$needed" ]; then
					log "daemon: auto-checks passed ${passes}x — auto-confirming"
					rm -f "$PENDING"; sync
					exit 0
				fi
			else
				passes=0
			fi
		fi
		sleep "$interval"
	done
}

# ---- rpc helper (called by /usr/libexec/rpcd/sysupgrade-confirm) ------------

do_rpc_confirm() { # <token> — token is MANDATORY on this path (anonymous ACL)
	[ -n "$1" ] || exit 1
	[ -f "$PENDING" ] || exit 1
	. "$PENDING"
	[ "$1" = "$TOKEN" ] || { log "rpc confirm DENIED: bad token"; exit 1; }
	rm -f "$PENDING"
	sync
	log "CONFIRMED via rpc token — revert timer disarmed"
	exit 0
}

case "$1" in
	"")            do_confirm ;;
	status)        do_status "$2" ;;
	arm)           do_arm ;;
	revert)        do_revert ;;
	_daemon)       do_daemon ;;
	_rpc_confirm)  do_rpc_confirm "$2" ;;
	*)             echo "usage: sysupgrade-confirm [status [--json]|arm|revert]" >&2; exit 1 ;;
esac
