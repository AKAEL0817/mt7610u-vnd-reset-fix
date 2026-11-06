#!/bin/sh
# verify-module.sh - verify the patched mt76x0u driver state on OpenWrt.
#
# Checks:
#   1. mt76x0u module is loaded
#   2. the vnd_reset parameter exists and is set to "skip" (N or 0)
#      (the parameter does not exist at all in the stock module)
#   3. an ieee80211 phy exists whose driver is mt76x0u (probe succeeded
#      for THIS driver, not just for any wireless card in the system)
#   4. the LATEST probe attempt is free of the failure signatures:
#        vendor request ... failed:-110
#        rx urb failed: -32
#      Only dmesg lines after the most recent probe start are counted:
#      every mt76x0 probe prints an "ASIC revision" line, so failures
#      logged by the stock driver earlier in the same boot (e.g. before
#      a module swap) do not cause a false FAIL.
#
# Exit code 0 = PASS, 1 = at least one check failed.

FAIL=0

echo "== 1. module loaded =="
if lsmod | grep -q '^mt76x0u'; then
	echo "mt76x0u: loaded"
else
	echo "mt76x0u: NOT loaded"
	FAIL=1
fi

echo "== 2. vnd_reset parameter =="
PARAM=/sys/module/mt76x0u/parameters/vnd_reset
if [ -f "$PARAM" ]; then
	V=$(cat "$PARAM")
	echo "vnd_reset = $V"
	case "$V" in
		N|0) echo "-> reset is SKIPPED (patched behaviour)" ;;
		*)   echo "-> reset is ENABLED (stock behaviour)"; FAIL=1 ;;
	esac
else
	echo "parameter not found - this is the STOCK module, patch not active"
	FAIL=1
fi

echo "== 3. wireless phy (owned by mt76x0u) =="
FOUND=""
for p in /sys/class/ieee80211/*; do
	[ -e "$p/device/driver" ] || continue
	DRV=$(basename "$(readlink "$p/device/driver")")
	if [ "$DRV" = "mt76x0u" ]; then
		FOUND="$FOUND ${p##*/}"
	fi
done
if [ -n "$FOUND" ]; then
	echo "mt76x0u phy found:$FOUND"
else
	echo "no phy owned by mt76x0u - probe did not create a wireless device"
	FAIL=1
fi

echo "== 4. failure signatures since latest probe =="
LOG=$(dmesg)
START=$(printf '%s\n' "$LOG" | grep -n 'ASIC revision' | tail -n 1 | cut -d: -f1)
if [ -n "$START" ]; then
	TAILPART=$(printf '%s\n' "$LOG" | tail -n "+$((START + 1))")
else
	echo "no probe start found in dmesg - scanning the whole buffer"
	TAILPART="$LOG"
fi
N110=$(printf '%s\n' "$TAILPART" | grep -c 'vendor request.*failed:-110')
N32=$(printf '%s\n' "$TAILPART" | grep -c 'rx urb failed: -32')
echo "vendor request -110 lines : $N110"
echo "rx urb failed -32 lines   : $N32"
[ "$N110" -gt 0 ] && FAIL=1
[ "$N32" -gt 0 ] && FAIL=1

echo "== result =="
if [ "$FAIL" -eq 0 ]; then
	echo "PASS: patched mt76x0u is active and the adapter probed cleanly"
else
	echo "FAIL: see checks above"
fi
exit $FAIL
