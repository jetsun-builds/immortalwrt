#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TOP="$(pwd)"
mkdir -p "$TOP/dist" "$TOP/build-logs"
exec > >(tee "$TOP/build-logs/sdk-build.log") 2>&1
SDK_URL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sdk_url"])' "$ROOT/sdk.lock.json")"
SDK_HASH="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sdk_sha256"])' "$ROOT/sdk.lock.json")"
curl --fail --location --retry 4 "$SDK_URL" -o "$TOP/sdk.tar.zst"
echo "$SDK_HASH  $TOP/sdk.tar.zst" | sha256sum -c -
mkdir "$TOP/sdk"
tar --zstd -xf "$TOP/sdk.tar.zst" -C "$TOP/sdk" --strip-components=1
cd "$TOP/sdk"
printf '%s\n' \
  'src-git base https://github.com/immortalwrt/immortalwrt.git^0c4cd0f9920a420a2ac95b49c1b62130769c08ae' \
  'src-git packages https://github.com/immortalwrt/packages.git^84bd86384928955b568988ca0e09e2c78c75173d' > feeds.conf
./scripts/feeds update base packages
./scripts/feeds install -p base libubox libnl-tiny zlib
./scripts/feeds install -p packages nlbwmon
test "$(git -C feeds/base rev-parse HEAD)" = "0c4cd0f9920a420a2ac95b49c1b62130769c08ae"
test "$(git -C feeds/packages rev-parse HEAD)" = "84bd86384928955b568988ca0e09e2c78c75173d"
cp -a "$ROOT/package/." feeds/packages/net/nlbwmon/
# Discard the SDK's preselected packages before selecting only nlbwmon.
touch .config
sed -i -E '/^CONFIG_PACKAGE_.*=/d; /^CONFIG_ALL(_KMODS|_NONSHARED)?=/d' .config
cat >> .config <<'CONFIG'
CONFIG_PACKAGE_nlbwmon=m
# CONFIG_SIGNED_PACKAGES is not set
# CONFIG_ALL is not set
# CONFIG_ALL_NONSHARED is not set
# CONFIG_ALL_KMODS is not set
CONFIG
make defconfig
make -j2 package/nlbwmon/compile CONFIG_AUTOREMOVE= V=s
mapfile -t PACKAGES < <(find bin/packages -type f -name 'nlbwmon-*.apk' -print)
test "${#PACKAGES[@]}" = "1"
cp "$PACKAGES" "$TOP/dist/"
cp "$ROOT/sdk.lock.json" "$TOP/dist/"
cp "$ROOT/README.md" "$TOP/dist/"
SOURCE_DIR="$(find build_dir/target-* -maxdepth 1 -type d -name 'nlbwmon-*' | head -1)"
test -n "$SOURCE_DIR"
BINARY="$SOURCE_DIR/nlbwmon"
test -f "$BINARY"
file "$BINARY" | tee "$TOP/dist/elf-info.txt"
readelf -h "$BINARY" >> "$TOP/dist/elf-info.txt"
readelf -d "$BINARY" | tee "$TOP/dist/elf-dynamic.txt"
python3 "$ROOT/verify-elf.py" "$ROOT/sdk.lock.json" "$TOP/dist/elf-dynamic.txt"
cp "$BINARY" "$TOP/dist/nlbwmon"
find staging_dir/toolchain-* -name '*gcc' -type f -o -name '*gcc' -type l > "$TOP/build-logs/compiler-paths.txt"
COMPILER="$(find staging_dir/toolchain-*/bin -name '*-gcc' | head -1)"
test -n "$COMPILER"
export STAGING_DIR="$TOP/sdk/staging_dir/target-x86_64_musl"
"$COMPILER" -Dtime=nlbw_test_time -I"$SOURCE_DIR" "$SOURCE_DIR/timing.c" "$ROOT/tests/timing-test.c" -o "$TOP/dist/timing-test-musl"
LOADER="$(find staging_dir/toolchain-* -name libc.so -type f | head -1)"
test -n "$LOADER"
"$LOADER" "$TOP/dist/timing-test-musl" | tee "$TOP/dist/musl-test-results.txt"
{
  echo "SDK: $SDK_URL"
  echo "SDK SHA256: $SDK_HASH"
  echo "Source: 29236be687927b0c81ee6e2642e7caa8787c4ad3"
  echo "Base feed: $(git -C feeds/base rev-parse HEAD)"
  echo "Packages feed: $(git -C feeds/packages rev-parse HEAD)"
  echo "Recipe release: 100"
  echo "Built at UTC: $(date -u +%FT%TZ)"
} > "$TOP/dist/build-info.txt"
(cd "$TOP/dist" && sha256sum -- * > SHA256SUMS)
