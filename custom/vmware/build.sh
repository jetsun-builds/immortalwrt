#!/usr/bin/env bash
set -euo pipefail
repo_root="$(pwd)"
custom_dir="$repo_root/custom/vmware"
version=25.12.2
archive="immortalwrt-imagebuilder-${version}-x86-64.Linux-x86_64.tar.zst"
base_url="https://downloads.immortalwrt.org/releases/${version}/targets/x86/64"
mkdir -p "$repo_root/build-work" "$repo_root/dist"
cd "$repo_root/build-work"
curl --fail --location --retry 5 --retry-delay 5 "$base_url/$archive" -o "$archive"
echo "b9b290f5ef60a22bccd5bdca9c1e7523b8fc84e60462afbf550e20db94acf2c6  $archive" | sha256sum -c -
tar --zstd -xf "$archive"
cd "${archive%.tar.zst}"
install -Dm644 "$custom_dir/network" files/etc/config/network
install -Dm755 "$custom_dir/99-vmware-router" files/etc/uci-defaults/99-vmware-router
# Keep a single squashfs EFI disk family, reusing the official packaged kernel.
sed -i -e '/^CONFIG_TARGET_ROOTFS_EXT4FS=/d' \
  -e '/^CONFIG_ISO_IMAGES=/d' -e '/^CONFIG_QCOW2_IMAGES=/d' \
  -e '/^CONFIG_VDI_IMAGES=/d' -e '/^CONFIG_VHDX_IMAGES=/d' \
  -e '/^CONFIG_GRUB_IMAGES=/d' .config
printf '\nCONFIG_VMDK_IMAGES=y\nCONFIG_GRUB_EFI_IMAGES=y\nCONFIG_TARGET_ROOTFS_SQUASHFS=y\n' >> .config
packages="$(tr '\n' ' ' < "$custom_dir/packages.txt")"
make image PROFILE=generic ROOTFS_PARTSIZE=1024 FILES="$PWD/files" PACKAGES="$packages" 2>&1 | tee "$repo_root/dist/build.log"
images="$PWD/bin/targets/x86/64"
vmdk="immortalwrt-${version}-x86-64-generic-squashfs-combined-efi.vmdk"
test -s "$images/$vmdk"
cp "$images/$vmdk" "$repo_root/dist/$vmdk"
manifest="$(find "$images" -maxdepth 1 -type f -name '*.manifest' -print -quit)"
test -n "$manifest"
cp "$manifest" "$repo_root/dist/packages.manifest"
cp "$custom_dir/README.md" "$repo_root/dist/README.md"
cp "$custom_dir/network" "$repo_root/dist/network.defaults"
cp "$custom_dir/packages.txt" "$repo_root/dist/requested-packages.txt"
qemu-img info --output=json "$repo_root/dist/$vmdk" > "$repo_root/dist/disk-info.json"
cd "$repo_root/dist"
sha256sum "$vmdk" > SHA256SUMS
