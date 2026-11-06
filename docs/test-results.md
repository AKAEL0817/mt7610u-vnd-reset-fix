# Test results

## Environment (OpenWrt)

| Item | Value |
| --- | --- |
| System | OpenWrt 24.10.8 (r29233-443ec4032a), x86/64, running as a VM |
| Kernel | 6.6.144 |
| mt76 source | snapshot `eb567bc7f9b692bbf1ddfe31dd740861c58ec85b` (2025-11-06) |
| Stock package | `kmod-mt76x0u 6.6.144.2025.11.06~eb567bc7-r1` |
| Patched package | `kmod-mt76x0u 6.6.144.2025.11.06~eb567bc7-r2` (PKG_RELEASE bumped; only this package replaced) |
| Adapter | USB passthrough by physical port; `0e8d:2870` → `0e8d:7610` |
| Firmware | `mt7610u.bin` / `mt7610e.bin` (from the stock package set) |

Method notes:

- Before the change, a VM snapshot was taken; the stock ipk remains reinstallable from the official feed — two independent rollback paths.
- The five sibling modules (`mt76`, `mt76-usb`, `mt76x02-lib`/`mt76x02-common`, `mt76x02-usb`, `mt76x0-common`) were **not** replaced. The patch touches only `mt76x0/usb_mcu.c`, which is compiled solely into `mt76x0u.ko`.
- Verification of the patched module before install: `vermagic=6.6.144 SMP mod_unload`, `parmtype=vnd_reset:bool` present in the `.ko`; the ipk's only version-pinned dependency is the kernel itself (`=6.6.144~50daf8372d971124fb3519e8d87e02ae-r1`, matching the target).
- After install: `opkg flag hold kmod-mt76x0u` prevents an `opkg upgrade` from restoring the stock driver.
- The adapter was physically power-cycled (unplug, 5 s, replug) before the decisive test, so the patched probe started from a cold device — the same starting condition as every stock-driver failure.

## Before — stock driver

Probe begins at uptime 394.96 s (module auto-load after package install) and grinds through retries until 447.83 s. Excerpt (full log: `dmesg-before-stock-driver.txt`, 141 lines):

```
[  394.963374] mt76x0u 2-1:1.0: ASIC revision: 76100002 MAC revision: 76502000
[  395.297872] mt76x0u 2-1:1.0: rx urb failed: -32
... (repeated; "mt76u_complete_rx: 22834 callbacks suppressed") ...
[  398.563546] mt76x0u 2-1:1.0: vendor request req:07 off:09a8 failed:-110
[  401.763002] mt76x0u 2-1:1.0: vendor request req:06 off:09a8 failed:-110
[  404.993037] mt76x0u 2-1:1.0: vendor request req:42 off:0230 failed:-110
[  447.774372] mt76x0u 2-1:1.0: vendor request req:06 off:0080 failed:-110
[  447.832903] mt76x0u: probe of 2-1:1.0 failed with error -110
```

Outcome: **no phy, no interface, adapter unusable.** This was the third independent reproduction (hypervisor host bare metal and a second VM environment produced the same signature).

## After — patched driver (`vnd_reset` default = skip)

Module state after loading: `/sys/module/mt76x0u/parameters/vnd_reset` reads `N` (the stock module has no such file — its presence alone proves the patched module is the loaded one).

Replug probe, complete (full log: `dmesg-after-patched-driver.txt`, 5 lines):

```
[ 6633.394600] usb 2-1: new high-speed USB device number 3 using xhci_hcd
[ 6633.984711] usb 2-1: reset high-speed USB device number 3 using xhci_hcd
[ 6634.173967] mt76x0u 2-1:1.0: ASIC revision: 76100002 MAC revision: 76502000
[ 6635.041416] mt76x0u 2-1:1.0: EEPROM ver:02 fae:01
[ 6635.102277] ieee80211 phy2: Selected rate control algorithm 'minstrel_ht'
```

Probe duration ≈ **1.7 s**. `vendor request ... -110` lines: **0**. `rx urb failed: -32` lines: **0**.

## Functional check (scan)

A test interface was created on the new phy (`iw phy phy2 interface add wlan0 type managed`, link up) and a scan performed:

- **2.4 GHz: 19 BSSs** received
- **5 GHz: 3 BSSs** received

Both radios receive real-world networks; the adapter is not merely probing, it is working. (The test interface was deleted afterwards; normal operation would configure the radio through the usual wireless configuration.)

## Summary

| Check | Stock | Patched |
| --- | --- | --- |
| ASIC/MAC read | OK | OK |
| Post-reset communication | dead | normal |
| `rx urb failed: -32` | flood | 0 |
| `vendor request failed: -110` | many | 0 |
| Probe result | fail (~50 s) | success (~1.7 s) |
| phy created | no | yes |
| 2.4 GHz scan | n/a | 19 BSSs |
| 5 GHz scan | n/a | 3 BSSs |

Persistence: the parameter defaults to *skip* in the compiled module, so the fix is active on every subsequent boot with no configuration files. The only persistence risk is a package upgrade replacing the module — mitigated by the opkg hold flag.

## Proxmox VE port — verified (2026-11-07)

| Item | Value |
| --- | --- |
| System | Proxmox VE 9.2, bare-metal host (laptop-class machine) |
| Kernel | 7.0.14-28-pve |
| Source tree | Ubuntu 7.0.0-43.43, submodule pin `49ecb900ee95547cf6e887aba22a5ce52c617b78` (identified via the headers package's `SOURCE` file; see `pve-build-guide.md`) |
| Patch | `patches/pve-7.0-vnd-reset.patch` — the same three hunks, applied with zero fuzz |
| Build | Out-of-tree (`M=`) against the official `proxmox-headers-7.0.14-28-pve`, gcc 14.2; only `mt76x0u` rebuilt |
| Adapter | The same physical adapter as the OpenWrt test, plugged directly into the host |

Method notes:

- Provenance checks: Proxmox's patch queue contains no mt76 patches; `mt76x0/usb.c` and `usb_mcu.c` are byte-identical between kernel.org v7.0.14 and the pinned Ubuntu tree.
- The built module's `vermagic` and `depends` are identical to the stock module's, and `modinfo` shows the `vnd_reset` parameter.
- The test was non-persistent by design: the stock on-disk module was never replaced; the patched module was loaded with `insmod` from a scratch path, so rollback is a single `rmmod`.
- Failure counting used a dmesg watermark (line count recorded before the plug); only lines logged after the plug were counted — the same discipline as `scripts/verify-module.sh` v2.
- The stock driver's failure on this same host (bare metal) was one of the original reproductions of the bug, so the before state is established for this environment too.

Result — plug sequence:

```
usb: new device 0e8d:2870 (virtual CD mode)
usb-storage detected -> modeswitch disconnect
usb: new device 0e8d:7610, Product: WiFi, Manufacturer: MediaTek
mt76x0u: ASIC revision: 76100002 MAC revision: 76502000
mt76x0u: EEPROM ver:02 fae:01
ieee80211 phy created (owned by mt76x0u); wireless interface registered
```

| Check | Stock (this host) | Patched |
| --- | --- | --- |
| ASIC/MAC read | OK | OK |
| Probe result | fail (-110) | success (< 1 s after enumeration) |
| `vendor request failed: -110` (after plug) | many | **0** |
| `rx urb failed: -32` (after plug) | flood | **0** |
| phy / interface created | no | yes |

Known gap: the host has no `iw` installed, so no scan was run in the PVE environment. Firmware load and MCU communication — the steps that fail with the stock driver — complete, and the interface registers; radio reception on this same adapter and driver path is proven by the OpenWrt scan above.
