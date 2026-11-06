# Problem analysis

## The device

A white-label "AC600" dual-band USB Wi-Fi adapter with an external antenna, built on the MediaTek MT7610U chipset.

- First enumeration: `0e8d:2870` — a virtual CD-ROM (driver disc, volume label `WA600AC_UN_V1`) that must be ejected / mode-switched
- After switching: `0e8d:7610` — the actual Wi-Fi device
- Chip identity as read by the driver: **ASIC revision 76100002, MAC revision 76502000**

## The failure, precisely

With the stock in-kernel `mt76x0u` driver, the probe sequence (OpenWrt, kernel 6.6.144) is:

```
usb 2-1: reset high-speed USB device number 2 using xhci_hcd
mt76x0u 2-1:1.0: ASIC revision: 76100002 MAC revision: 76502000
mt76x0u 2-1:1.0: rx urb failed: -32            <- repeated, kernel suppresses 10k+ more
mt76x0u 2-1:1.0: vendor request req:07 off:09a8 failed:-110
mt76x0u 2-1:1.0: vendor request req:06 off:09a8 failed:-110
mt76x0u 2-1:1.0: vendor request req:42 off:0230 failed:-110
... ~50 seconds of this ...
mt76x0u: probe of 2-1:1.0 failed with error -110
```

Reading the ASIC/MAC revision — itself a vendor-request exchange — **succeeds**. Everything after dies. The full log is in `dmesg-before-stock-driver.txt`.

## What was ruled out, and how

| Hypothesis | Test | Result |
| --- | --- | --- |
| Dead hardware | Plug into a Windows 10 PC | Works instantly (vendor driver) |
| Missing firmware | `mt7610u.bin` / `mt7610e.bin` present on all test systems | Ruled out |
| Wrong driver | Chipset is mainline-supported since kernel 4.19; module loads and binds | Ruled out |
| USB port / power | Fails identically on xHCI and EHCI ports; enumerates cleanly every time | Ruled out |
| New-kernel regression | Identical `-110` signature documented on kernels 4.4 through 6.6 | Ruled out |
| Distribution-specific | Reproduced on a Debian-based hypervisor host (kernel 7.0, bare metal), in an OpenWrt VM (6.6, USB passthrough), and reported for a Kali VM in the distro's own bug tracker (#8453) with a byte-identical log | Ruled out |
| "Plug and play per vendor docs" | A well-known vendor guide (ALFA, for their AWUS036ACHM) documents this chipset as plug-and-play. Its expected device fingerprint (an ALFA OUI MAC, direct Wi-Fi enumeration, no driver-CD mode) describes **a different board population** than white-label dual-mode sticks. The guide's troubleshooting table has no entry for a probe-time `-110`, because its hardware never produces one | Different hardware revision, not a procedure error |

## Root cause

Between the successful revision reads and the firmware upload, `mt76x0u_load_firmware()` issues a **vendor reset** (`mt76x02u_mcu_fw_reset()` in current mt76 code; `mt76x0_vendor_reset()` in 4.19-era code). On this hardware revision, the MCU never recovers from that reset: it stops acknowledging vendor requests (USB control transfers time out, `-110` / `-ETIMEDOUT`) and bulk RX URBs stall (`-32` / `-EPIPE`). Every subsequent probe step inherits the timeout.

The strongest external corroboration: [openwrt/mt76 Issue #454](https://github.com/openwrt/mt76/issues/454) reports the **same log signature** (an "rx urb failed" flood plus vendor-request failures) for an AVM `057c:8502` adapter whose log shows the **identical** `ASIC revision: 76100002 MAC revision: 76502000`, and records that gating the vendor reset fixed it (2.4/5 GHz working). An October 2026 kernel patch documents the same failure class for the sibling MT7601U: certain hardware revisions' MCUs go unresponsive during mainline-driver initialisation, while the vendor driver — which never takes that path — is unaffected.

## Why "it worked in a Kali VM once" doesn't contradict this

Reports of generic MT7610U sticks working under Linux exist alongside the failure reports, including in Kali (whose bug tracker simultaneously carries the identical failure). The chipset shipped in many board/EEPROM/revision combinations over a decade; only some revisions hit this. Anecdotes in either direction don't generalise — the log signature on *your* unit decides.

## The fix, restated

Skip the reset for devices that can't survive it. One call site, gated by a module parameter that defaults to skipping:

```c
	if (vnd_reset)
		mt76x02u_mcu_fw_reset(dev);
```

Devices that need the reset can opt back in with `vnd_reset=1`.

— Full build and test evidence: `build-guide.md`, `test-results.md`.
