#!/bin/sh
# verify-module.sh - verify the patched mt76x0u driver state on OpenWrt.
#
# Checks:
#   1. mt76x0u module is loaded
#   2. the vnd_reset parameter exists and is set to "skip" (N or 0)
#      (the parameter does not exist at all in the stock module)
#   3. an ieee80211 phy was created (probe succeeded)
#   4. dmesg contains neither failure signature:
#        vendor request ... failed:-110
#        rx urb failed: -32
#
# Exit code 0 = PASS, 1 = at least one check failed.
# Note: check 4 inspects the whole dmesg ring buffer; run shortly after
# a fresh boot / module load / adapter replug for a clean reading.

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

echo "== 3. wireless phy =="
PHYS=$(ls /sys/class/ieee80211/ 2>/dev/null)
if [ -n "$PHYS" ]; then
	echo "phy found: $PHYS"
else
	echo "no phy - probe did not create a wireless device"
	FAIL=1
fi

echo "== 4. failure signatures in dmesg =="
N110=$(dmesg | grep -c 'vendor request.*failed:-110')
N32=$(dmesg | grep -c 'rx urb failed: -32')
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
