# mt7610u-vnd-reset-fix

**Make white-label MT7610U USB Wi-Fi adapters work on Linux by skipping one fatal step in the stock `mt76x0u` driver: the firmware vendor reset.**

Some MT7610U hardware revisions are permanently deafened by the vendor reset that the mainline `mt76x0u` driver performs while loading firmware. The chip answers everything up to that point, then never responds again. This project documents the failure, proves the root cause with before/after kernel logs, and ships a small, portable patch that gates the reset behind a module parameter — defaulting to *skip*.

> 中文摘要：部分硬件版本的 MT7610U（ASIC 76100002）在 Linux 主线驱动加载固件执行 Vendor Reset 后失去响应，表现为 `vendor request` 大量 `-110` 超时与 `rx urb failed: -32` 刷屏、探针失败。本补丁为驱动增加 `vnd_reset` 参数并默认跳过该复位，实测设备恢复双频正常工作。

## Symptoms (stock driver)

Probing the adapter produces, in order:

1. `ASIC revision: 76100002 MAC revision: 76502000` — reads fine
2. A flood of `rx urb failed: -32`
3. `vendor request req:07/06/42 ... failed:-110` — every request times out
4. After ~50 s: `probe of ... failed with error -110` — no wireless device, ever

The same adapter works instantly on Windows with the vendor driver, and the identical failure reproduces across kernels and distributions (bare metal, VM passthrough, multiple distros), which rules out missing firmware, missing drivers, and cabling/power issues.

## Root cause

In `mt76x0u_load_firmware()` (`mt76x0/usb_mcu.c`), the driver calls the firmware vendor reset (`mt76x02u_mcu_fw_reset()` in current code, `mt76x0_vendor_reset()` in older trees) after setting up USB DMA, before uploading firmware. On affected hardware revisions the MCU does not survive that reset: it stops answering vendor requests entirely, so every later step of the probe times out.

## The fix

[`patches/openwrt-6.6-vnd-reset.patch`](patches/openwrt-6.6-vnd-reset.patch) — a standalone git patch against mt76 snapshot `eb567bc7`:

- Adds a `vnd_reset` bool module parameter to `mt76x0u`, **default `false` (skip the reset)**
- Wraps the single `mt76x02u_mcu_fw_reset(dev);` call in `if (vnd_reset)`
- `vnd_reset=1` restores the exact upstream behaviour

That is the entire change: one gated call, one parameter.

## Verified results

Environment: OpenWrt 24.10.8, kernel 6.6.144, mt76 `2025.11.06~eb567bc7`, adapter passed through to a VM (USB `0e8d:2870` → `0e8d:7610`, ASIC 76100002 / MAC 76502000). Only the `kmod-mt76x0u` package was replaced; all other mt76 modules stayed stock.

| Check | Stock driver | Patched driver |
| --- | --- | --- |
| ASIC/MAC read | OK | OK |
| Communication after vendor reset | timeouts | normal |
| `rx urb failed: -32` | flood (10k+ suppressed) | **0** |
| `vendor request failed: -110` | many | **0** |
| Probe | fails after ~50 s | **succeeds in ~1.7 s** |
| ieee80211 phy | none | created |
| 2.4 GHz scan | n/a | 19 BSSs |
| 5 GHz scan | n/a | 3 BSSs |

Full logs: [`docs/dmesg-before-stock-driver.txt`](docs/dmesg-before-stock-driver.txt) · [`docs/dmesg-after-patched-driver.txt`](docs/dmesg-after-patched-driver.txt) · analysis in [`docs/`](docs/).

## Applicability — read before using

- **Verified only for:** OpenWrt 24.10.8 / kernel 6.6.144 / mt76 snapshot `eb567bc7`, on an adapter reporting ASIC revision `76100002`.
- The patch context is small and stable; it should apply to nearby mt76 versions with minor fuzz, but **an unverified combination is an experiment, not a fix** — check your `dmesg` signature first (it must match the symptoms above).
- Proxmox VE (kernel 7.0.14-28-pve) port: **planned, NOT yet ported or verified.** There is deliberately no `pve-7.x` patch in this repo until it has been built and tested the same way. Do not treat this project as PVE support yet.
- If your adapter works with the stock driver, you don't need this.

## Quick start (OpenWrt)

1. Build the patched package with the SDK of your exact OpenWrt release — see [`docs/build-guide.md`](docs/build-guide.md) (includes the pitfalls: the mt76 package builds its test tool unconditionally and needs `libnl-tiny` headers in a full tree; SDK trees need `gawk` and `umask 022`).
2. Back up. On a VM, take a snapshot; keep the stock `.ko` / stock ipk for rollback.
3. Install only the patched `kmod-mt76x0u` ipk, reload the module, replug the adapter.
4. Verify with [`scripts/verify-module.sh`](scripts/verify-module.sh) on the target system.
5. Recommended: `opkg flag hold kmod-mt76x0u` so a later `opkg upgrade` doesn't silently restore the stock driver.

The patched module needs no configuration: the parameter defaults to skipping the reset, so it also survives reboots as-is.

## References

- [openwrt/mt76 Issue #454](https://github.com/openwrt/mt76/issues/454) — same failure and workaround on an AVM `057c:8502` adapter with identical ASIC/MAC revisions; this project's patch is a port of that idea to the current mt76 code layout
- [Launchpad bug 1716301, comment 53](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1716301/comments/53) — origin of the `vnd_reset` approach
- ALFA's MT7610U guide describes the chipset as plug-and-play — true for their own board (AWUS036ACHM); white-label dual-mode boards are a different hardware population, see [`docs/problem-analysis.md`](docs/problem-analysis.md)

## License

GPL-2.0-only, matching the Linux kernel driver code this patch modifies. The patch is provided as-is, without warranty; you are responsible for testing it on your own hardware.
