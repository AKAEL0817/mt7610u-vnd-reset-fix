# Prebuilt package

`kmod-mt76x0u_6.6.144.2025.11.06~eb567bc7-r2_x86_64.ipk` — the exact package that was built and verified on real hardware (see [`../docs/test-results.md`](../docs/test-results.md)). It is attached directly to the v1.0.0 release on this project's [Releases page](https://github.com/AKAEL0817/mt7610u-vnd-reset-fix/releases) (GitHub shows the file name with `~` replaced by `.` — cosmetic only); this directory documents its checksum and applicability.

**Use it only on the exact platform it was built for:**

- OpenWrt **24.10.8**, target **x86/64**
- Kernel **6.6.144** — the package is vermagic-locked to this kernel build and will not load on any other

For any other OpenWrt release, target, or kernel, build from the patch instead: [`../docs/build-guide.md`](../docs/build-guide.md).

SHA256:

```
c8d3e4314bfc5a58918eb91631a2972f1d781ff5bb312a7ccace71d816b84262  kmod-mt76x0u_6.6.144.2025.11.06~eb567bc7-r2_x86_64.ipk
```

Install and verify: follow "Quick start" in the top-level README (steps 2–5).

## Proxmox VE

`mt76x0u_7.0.14-28-pve_vnd-reset.ko` — the verified PVE build, attached to the **v1.1.0** release.

- Kernel **7.0.14-28-pve only** (vermagic-locked; any other kernel release needs a rebuild — see [`../docs/pve-build-guide.md`](../docs/pve-build-guide.md))
- SHA256:

```
6b88d32c410c2c2d1e564e997361ac356532e019b254c6e918b7250a7bc1ffb9  mt76x0u_7.0.14-28-pve_vnd-reset.ko
```

- Use: test-load with `insmod`, or install as `mt76x0u.ko` under `/lib/modules/7.0.14-28-pve/updates/` plus `depmod -a 7.0.14-28-pve` for persistence.
