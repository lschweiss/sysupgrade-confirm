#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# openwrt-ci runtime test (packages-feed convention): invoked in the CI
# sandbox after install as `test.sh <package> <version>`. The sandbox is not
# a dual-firmware board, so exercise everything that must work regardless:
# binary present, status runs, board gate refuses arm (which must be a
# clean, non-crash failure), keep.d list present.
set -e

case "$1" in
sysupgrade-confirm)
	sysupgrade-confirm status | grep -q . || exit 1
	sysupgrade-confirm status --json | grep -q '"pending"' || exit 1
	# unsupported sandbox board MUST refuse to arm (exit non-zero, no crash)
	if sysupgrade-confirm arm 2>/dev/null; then
		echo "arm succeeded on an unsupported board — gate broken" >&2
		exit 1
	fi
	[ -f /lib/upgrade/keep.d/sysupgrade-confirm ] || exit 1
	[ -x /usr/libexec/rpcd/sysupgrade-confirm ] || exit 1
	echo "OK"
	;;
esac
exit 0
