#!/bin/bash
# ABI/symbol exactness: the fork's globally-defined symbols must be exactly the
# upstream set (same names, no additions/removals). Addresses/sizes may differ.
#
# usage: harness/abi.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/abi"; mkdir -p "$BUILD"
CC=${CC:-clang}

$CC -O2 -ffp-contract=off -I "$ROOT/upstream" -c "$ROOT/lib/stb_image_write.c" -o "$BUILD/up.o" || exit 1
$CC -O2 -ffp-contract=off -I "$ROOT/src"      -c "$ROOT/lib/stb_image_write.c" -o "$BUILD/fork.o" || exit 1

nm -g --defined-only "$BUILD/up.o"   | awk '{print $3}' | sort > "$BUILD/up.syms"
nm -g --defined-only "$BUILD/fork.o" | awk '{print $3}' | sort > "$BUILD/fork.syms"

if diff -u "$BUILD/up.syms" "$BUILD/fork.syms" > "$BUILD/abi.diff"; then
    echo "PASS: ABI symbols identical ($(wc -l < "$BUILD/up.syms") exported)"
else
    echo "FAIL: exported symbol set differs"
    cat "$BUILD/abi.diff"
    exit 1
fi
