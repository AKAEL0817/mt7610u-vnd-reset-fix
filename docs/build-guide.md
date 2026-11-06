# Build guide (OpenWrt)

How the verified `kmod-mt76x0u` r2 package was produced. The same recipe rebuilds it for any OpenWrt 24.10.x x86/64 target running the matching release; for other targets/releases, use that release's SDK and expect to re-check the patch context.

## Ingredients

- OpenWrt **SDK** for your exact release/target (here: 24.10.8, x86/64, gcc 13.3.0 musl). Verify the tarball against the release `sha256sums`.
- The mt76 package recipe from the same release. The SDK's own `package/` tree does **not** contain mt76; the base feed is a full-repo clone. A lighter route that works: take `package/kernel/mt76` and `package/kernel/mac80211` from the release tag archive (e.g. GitHub's `v24.10.8` tarball) and drop them into the SDK's `package/kernel/`.
- This repo's patch: `patches/openwrt-6.6-vnd-reset.patch`.

## Host requirements (learned the hard way)

- `umask 022` — the build refuses other umasks ("Please build with umask 022").
- `awk` must be **gawk**. With mawk, `include/scan.awk` fails (`function asort never defined`) and the package index silently loses packages ("No rule to make target 'package/kernel/mt76/compile'").
- Usual build prerequisites: gcc, make, python3, perl, zstd, gettext, libncurses-dev, libssl-dev, flex, bison, file, rsync, unzip.

## Steps

```sh
tar --zstd -xf openwrt-sdk-24.10.8-x86-64_*.tar.zst
cd openwrt-sdk-24.10.8-x86-64_*/

# package recipes (from the v24.10.8 tree)
cp -r <openwrt-24.10.8>/package/kernel/mt76     package/kernel/
cp -r <openwrt-24.10.8>/package/kernel/mac80211 package/kernel/

# the fix
cp patches/openwrt-6.6-vnd-reset.patch \
   package/kernel/mt76/patches/900-mt76x0u-optional-vendor-reset.patch
sed -i 's/^PKG_RELEASE=1/PKG_RELEASE=2/' package/kernel/mt76/Makefile

umask 022
make defconfig
# enable (as modules) at least:
#   kmod-mt76-core kmod-mt76-usb kmod-mt76x02-common
#   kmod-mt76x02-usb kmod-mt76x0-common kmod-mt76x0u
# (append CONFIG_PACKAGE_<name>=m to .config, then `make defconfig` again)

make -j$(nproc) package/kernel/mt76/compile
ls bin/targets/x86/64/packages/kmod-mt76x0u_*.ipk
```

The mt76 Makefile pins its source: `PKG_SOURCE_VERSION=eb567bc7...`, `PKG_SOURCE_DATE=2025-11-06` — confirm the recipe you use matches the patch's target snapshot before building.

## Pitfall: the package builds a test tool unconditionally

`package/kernel/mt76`'s `Build/Compile` always runs the CMake build of `tools/` (the `mt76-test` utility), regardless of whether the `mt76-test` package is selected. That tool needs `libnl-tiny` headers (`unl.h`). In a full OpenWrt tree they are always present; in a minimal SDK tree the build dies with:

```
tools/mt76-test.h:10:10: fatal error: unl.h: No such file or directory
```

Deselecting the `mt76-test` package does **not** help (the compile step is unconditional). Either provide `libnl-tiny` (copy `package/libs/libnl-tiny` in and build it first), or — if you only need the kernel modules — skip the tools line in your *local build tree's* Makefile:

```make
# in Build/Compile, replace:
#	$(MAKE) -C $(PKG_BUILD_DIR)/tools
# with:
	@true # mt76-test tool not needed for the driver packages
```

This changes nothing in the produced driver modules.

## Sanity-check the artifact before installing

```sh
# unpack the ipk (it is a tar.gz of control.tar.gz + data.tar.gz)
strings data/lib/modules/6.6.144/mt76x0u.ko | grep -E 'vermagic|vnd_reset|parmtype'
# expect: vermagic=6.6.144 ... ; a "vnd_reset" name and "parmtype=vnd_reset:bool"
```

Also read the ipk `control` file: the `Depends:` kernel pin must match your target's kernel package exactly (the build system enforces this at install time — treat a refusal as a stop sign, not something to force).

## Install, verify, roll back

```sh
# on the target (back up first: VM snapshot and/or keep the stock ipk)
opkg install kmod-mt76x0u_<version>-r2_x86_64.ipk   # upgrades r1 -> r2, touches nothing else
rmmod mt76x0u; modprobe mt76x0u                      # default already skips the reset
cat /sys/module/mt76x0u/parameters/vnd_reset         # expect: N
# physically replug the adapter, then:
sh verify-module.sh                                  # from this repo's scripts/
opkg flag hold kmod-mt76x0u                          # protect from opkg upgrade
```

Rollback: reinstall the stock package from the official feed (`opkg install --force-reinstall kmod-mt76x0u` after removing the hold), or restore the pre-change snapshot.

File-transfer footnote: minimal OpenWrt images have no SFTP server subsystem and no `base64`, so `scp` from a modern OpenSSH client fails in a confusing way. Staging the ipk on any HTTP server the target can reach and using the target's `wget` is boring and reliable.
