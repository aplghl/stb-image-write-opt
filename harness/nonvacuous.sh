#!/bin/bash
# Non-vacuous test proof: deliberately corrupt the candidate in a way that
# changes encoded output, then confirm the differential suite FAILS. If the
# corrupted build passes, the suite is not actually checking anything.
#
# usage: harness/nonvacuous.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP="$ROOT/build/nonvac_src"
rm -rf "$TMP" && mkdir -p "$TMP"
cp "$ROOT/src/stb_image_write.h" "$TMP/stb_image_write.h"

# Corrupt the SSE2 match kernel so it reports one extra matched byte. This
# changes LZ77 match lengths and therefore the compressed byte stream.
sed -i 's|return (unsigned)(i + __builtin_ctz(~mask));|return (unsigned)(i + __builtin_ctz(~mask)) + 1;|' \
    "$TMP/stb_image_write.h"

if ! grep -q "__builtin_ctz(~mask)) + 1;" "$TMP/stb_image_write.h"; then
    echo "SETUP FAIL: corruption did not apply (did the source change?)"
    exit 2
fi

echo "== non-vacuous: running differential against a deliberately corrupt candidate =="
if SRC_DIR="$TMP" QUIET=1 FULL=0 bash "$ROOT/harness/diff.sh" -O2 > "$ROOT/build/nonvac.log" 2>&1; then
    echo "FAIL: corrupted candidate PASSED the suite -> suite is vacuous"
    tail -5 "$ROOT/build/nonvac.log"
    exit 1
else
    echo "PASS: corrupted candidate correctly FAILED"
    grep -E 'FAIL:' "$ROOT/build/nonvac.log" | tail -1
fi
