# Build guide (Proxmox VE, kernel 7.0.14-28-pve)

How the verified PVE build of the patched `mt76x0u` was produced. The method matters
more than the exact commands: **the source tree is identified from the target kernel's
own packaging, not guessed.**

## 1. Identify the exact source tree

Proxmox kernels are Ubuntu-based with a Proxmox patch queue on top. For 7.0.14-28-pve:

1. Download the official headers package `proxmox-headers-7.0.14-28-pve` from the
   Proxmox repository and verify its SHA256 against the repo `Packages` index.
   Extract it locally (`dpkg -x`) — nothing needs to be installed on the host.
2. The headers package ships `usr/share/doc/proxmox-headers-*/SOURCE`, which names the
   exact build source: `pve-kernel.git` at commit `fd2f0d6a30a03587b447a70aff7de41cb58373a1`.
3. In that commit, `submodules/ubuntu-kernel` is pinned to
   `49ecb900ee95547cf6e887aba22a5ce52c617b78` (Ubuntu 7.0.0-43.43). Proxmox mirrors it at
   `git.proxmox.com/git/mirror_ubuntu-kernels.git`.
4. Sanity checks performed: Proxmox's own patch queue at that commit contains **no mt76
   patches at all**, and `mt76x0/usb.c` + `mt76x0/usb_mcu.c` are byte-identical between
   kernel.org v7.0.14 and the Ubuntu pin. The OpenWrt patch therefore applies to this
   tree with **zero fuzz**.

## 2. Build (out-of-tree, only mt76x0u)

Build host requirements:

- A compiler matching the kernel's series: the kernel was built with Debian gcc
  **14.2.0**; Ubuntu gcc-14 (14.2.0) works (kbuild prints a "compiler differs" warning —
  cosmetic).
- `libdw1` + `libelf1` — the headers' prebuilt `gendwarfksyms` needs them.
- `dwarves` (pahole).

```sh
KDIR=<extracted headers>/usr/src/linux-headers-7.0.14-28-pve
MT=<ubuntu tree>/drivers/net/wireless/mediatek/mt76
patch -p1 -d "$MT" < patches/pve-7.0-vnd-reset.patch   # paths are kernel-tree relative
make -C "$KDIR" M="$MT/mt76x0" CC=gcc-14 modules
```

Only `mt76x0u.ko` is needed; the sibling modules already in the kernel are used as-is.
Check the result before deploying: `vermagic` must read
`7.0.14-28-pve SMP preempt mod_unload modversions`, `depends` must match the stock
module, and `modinfo` must show `parm: vnd_reset`.

**srcversion caveat:** the stock module's `srcversion` could *not* be reproduced by any
out-of-tree build (identical `mt76x0` sources produced different values from different
trees). The field evidently hashes more than the module's own sources (full in-tree
build context). It is informational only — the loader checks vermagic and symbol CRCs
(taken from the official `Module.symvers`), not srcversion. Don't chase it.

## 3. Test (non-persistent, fully reversible)

On the host, with the adapter **not** passed through to any VM:

```sh
modprobe mt76x0-common && modprobe mt76x02-usb     # stock dependency chain
insmod /tmp/mt76x0u.ko                             # explicit path; not installed
cat /sys/module/mt76x0u/parameters/vnd_reset       # expect: N
# note the current dmesg line count, then plug the adapter in and read only new lines
```

Pass criteria (same as OpenWrt): modeswitch `0e8d:2870` → `0e8d:7610`, ASIC/MAC read OK,
a phy owned by `mt76x0u`, a wireless interface registered, and **zero**
`vendor request ... -110` / `rx urb failed: -32` lines after the plug.
Rollback is `rmmod mt76x0u` — the stock on-disk module was never touched.

## 4. Persistence (optional)

Copy the built `mt76x0u.ko` into `/lib/modules/7.0.14-28-pve/updates/` and run
`depmod -a 7.0.14-28-pve`; modules in `updates/` take precedence over the stock ones.
Note the host may blacklist `mt76x0u` (e.g. if the adapter is normally passed through
to a VM) — a blacklist blocks *automatic* loading only; remove it if the host itself
should drive the adapter. A kernel update to a new `-pve` release requires a rebuild
against that release's headers and source pin; the patch itself is expected to keep
applying, but treat every new kernel as unverified until re-tested.
