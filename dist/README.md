# Prebuilt package

`kmod-mt76x0u_6.6.144.2025.11.06~eb567bc7-r2_x86_64.ipk` — the exact package that was built and verified on real hardware (see [`../docs/test-results.md`](../docs/test-results.md)). It is distributed as a zipped asset on this project's [Releases page](https://github.com/AKAEL0817/mt7610u-vnd-reset-fix/releases) (GitHub does not accept `.ipk` uploads); this directory documents its checksum and applicability.

**Use it only on the exact platform it was built for:**

- OpenWrt **24.10.8**, target **x86/64**
- Kernel **6.6.144** — the package is vermagic-locked to this kernel build and will not load on any other

For any other OpenWrt release, target, or kernel, build from the patch instead: [`../docs/build-guide.md`](../docs/build-guide.md).

SHA256:

```
c8d3e4314bfc5a58918eb91631a2972f1d781ff5bb312a7ccace71d816b84262  kmod-mt76x0u_6.6.144.2025.11.06~eb567bc7-r2_x86_64.ipk
```

Install and verify: follow "Quick start" in the top-level README (steps 2–5).
