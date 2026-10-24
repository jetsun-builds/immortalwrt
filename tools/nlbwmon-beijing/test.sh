#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/.test-work"
mkdir -p "$WORK"
if [ ! -d "$WORK/upstream/.git" ]; then
  git init "$WORK/upstream"
  git -C "$WORK/upstream" fetch --depth 1 https://github.com/jow-/nlbwmon.git 29236be687927b0c81ee6e2642e7caa8787c4ad3
fi
git -C "$WORK/upstream" checkout --detach --force 29236be687927b0c81ee6e2642e7caa8787c4ad3
cp "$WORK/upstream/timing.c" "$WORK/stock-timing.c"
patch --batch --fuzz=0 -d "$WORK/upstream" -p1 < "$ROOT/package/patches/100-local-midnight-daily.patch"
# Upstream compares unsigned mday with an int; allow that existing warning.
cc -Wall -Wextra -Werror -Wno-error=sign-compare -Dtime=nlbw_test_time -I"$WORK/upstream" "$WORK/stock-timing.c" "$ROOT/tests/timing-test.c" -o "$WORK/stock-test"
cc -Wall -Wextra -Werror -Wno-error=sign-compare -Dtime=nlbw_test_time -I"$WORK/upstream" "$WORK/upstream/timing.c" "$ROOT/tests/timing-test.c" -o "$WORK/patched-test"
"$WORK/patched-test"
"$WORK/stock-test" --headers > "$WORK/stock-headers.txt"
"$WORK/patched-test" --headers > "$WORK/patched-headers.txt"
diff -u "$WORK/stock-headers.txt" "$WORK/patched-headers.txt"
"$WORK/stock-test" --unchanged > "$WORK/stock-other-intervals.txt"
"$WORK/patched-test" --unchanged > "$WORK/patched-other-intervals.txt"
diff -u "$WORK/stock-other-intervals.txt" "$WORK/patched-other-intervals.txt"
echo "PASS: serialized interval headers and non-daily intervals unchanged"
if "$WORK/stock-test" > "$WORK/stock-boundaries.txt" 2>&1; then
  echo "ERROR: unpatched source unexpectedly passed midnight tests" >&2
  exit 1
fi
echo "PASS: midnight tests detect the original bug"
