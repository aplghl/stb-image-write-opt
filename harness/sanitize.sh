#!/bin/bash
# Sanitizer gate: AddressSanitizer + UBSan over the encode matrix, including
# padded-stride and malformed parameter combinations, so the runtime-dispatched
# SIMD (and scalar fallback) paths are exercised. Any sanitizer report fails.
#
# usage: harness/sanitize.sh [extra flags...]
#   SAN=...   sanitizer set (default "address,undefined")
#   CC=clang
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"
CC=${CC:-clang}
FLAGS=${*:-"-O1 -g -march=x86-64-v3 -ffp-contract=off"}
SAN=${SAN:-"address,undefined"}
SANFLAGS="-fsanitize=$SAN -fno-sanitize-recover=all -fno-omit-frame-pointer"
# Scoped off: the pre-existing upstream JPEG bit-writer shift (see ignorelist).
IGNORE="-fsanitize-ignorelist=$ROOT/harness/ubsan_ignorelist.txt"

echo "== sanitizers: $FLAGS $SANFLAGS =="
$CC $FLAGS $SANFLAGS $IGNORE -I "$ROOT/src" -I "$ROOT/upstream" "$ROOT/tools/write_dump.c" -lm -o "$BUILD/write_san" || exit 1

fail=0; n=0
run() {
    local out
    out=$("$BUILD/write_san" "$@" 2>&1 >/dev/null); local rc=$?
    n=$((n + 1))
    if [ $rc -gt 1 ] || echo "$out" | grep -qE "Sanitizer|runtime error"; then
        echo "SANITIZER: $* (rc=$rc)"
        echo "$out" | head -12
        fail=1
    fi
}

for dims in 1x1 1x9 9x1 3x5 16x16 17x33 64x48; do
    for mode in grad plasma random flat; do
        for fmt in png bmp tga hdr jpg; do
            for comp in 1 3 4; do
                run "gen:$mode" "$fmt" "$comp" 8 --dims "$dims"
                run "gen:$mode" "$fmt" "$comp" 90 --dims "$dims" --flip 1
            done
        done
        # padded strides are only meaningful for png but harmless to pass elsewhere
        for c in 1 3 4; do
            run "gen:$mode" png "$c" 8 --dims "$dims" --stride $(( ${dims%x*} * c + 7 ))
        done
    done
done

for rel in corpus/plasma_512.png corpus/grad_640_480_rgba.png upstream/tests/pngsuite/primary/basn2c16.png; do
    [ -e "$ROOT/$rel" ] || continue
    for fmt in png bmp tga hdr jpg; do
        for comp in 1 2 3 4; do
            run "$ROOT/$rel" "$fmt" "$comp" 8 --incomp "$comp"
            run "$ROOT/$rel" "$fmt" "$comp" 90 --incomp "$comp" --flip 1
        done
    done
done

if [ "$fail" -eq 0 ]; then echo "PASS: sanitizers clean ($n inputs)"; else echo "FAIL: sanitizer error"; fi
exit $fail
