# Patches

| File | Target | Status |
| --- | --- | --- |
| `openwrt-6.6-vnd-reset.patch` | mt76 snapshot `eb567bc7` (OpenWrt 24.10.8, kernel 6.6.144) | **Verified** — built, installed, and tested on real hardware; see `docs/test-results.md` |
| `pve-7.0-vnd-reset.patch` | Proxmox VE kernel 7.0.14-28-pve (Ubuntu 7.0.0-43.43 tree) | **Verified** — built out-of-tree against the official headers and tested on a bare-metal PVE host; see `docs/test-results.md` and `docs/pve-build-guide.md` |

## What the patch does

One file, three hunks, against `mt76x0/usb_mcu.c`:

1. `#include <linux/moduleparam.h>`
2. A `vnd_reset` bool module parameter (default `false`) with a `MODULE_PARM_DESC`
3. The single firmware-reset call in `mt76x0u_load_firmware()`:

```c
	if (vnd_reset)
		mt76x02u_mcu_fw_reset(dev);
```

Apply with `git apply`, `git am`, or `patch -p1`. The OpenWrt patch's paths are relative to the mt76 source tree root; the PVE patch's paths are relative to the **kernel** source tree root (`drivers/net/wireless/mediatek/mt76/...`). In an OpenWrt build tree, drop the patch into `package/kernel/mt76/patches/` (a `900-` prefix keeps it after the stock patches) and bump `PKG_RELEASE`. For PVE, follow `docs/pve-build-guide.md`.
