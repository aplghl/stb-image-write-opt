#!/bin/bash
# Portability gate: build the candidate under supported configurations and
# cross-targets, and run a quick byte-exact check against the oracle for the
# native ones. Cross-targets are compile-only (no matching runtime here).
#
# usage: harness/portable.sh
#   CC (default clang), ZIG_CC (default "zig cc")
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/portable"
mkdir -p "$BUILD"
if [ -z "${CC:-}" ]; then
    CC=$(command -v clang 2>/dev/null || command -v gcc 2>/dev/null || echo cc)
fi
ZIG_CC=${ZIG_CC:-"zig cc"}

# Native configs: <name>|<flags>. The oracle is built with the SAME toggles so
# format-disabling configs are compared fairly.
CONFIGS=(
  "default|-O2"
  "no_simd|-O2 -DSTBIW_NO_SIMD"
  "arch_v2|-O3 -march=x86-64-v2 -ffp-contract=off"
  "arch_v3|-O3 -march=x86-64-v3 -ffp-contract=off"
  # NOTE: STBI_WRITE_NO_STDIO is not exercised here: upstream defines
  # stbi_write_hdr_to_func only inside the !NO_STDIO block (line ~812), so the
  # oracle itself fails to link write_dump with that toggle. Pre-existing.
)

SUBSET=(
  "gen:plasma|png|3|8|--dims 128x96"
  "gen:random|png|3|8|--dims 96x128"
  "gen:grad|png|4|8|--dims 129x65"
  "gen:plasma|jpg|3|85|--dims 128x96"
  "gen:grad|bmp|3|8|--dims 64x64"
  "gen:grad|tga|4|8|--dims 64x64"
  "gen:plasma|hdr|3|8|--dims 64x64"
)

fail=0
for c in "${CONFIGS[@]}"; do
    name=${c%%|*}; flags=${c#*|}
    printf '%-12s ' "$name"
    if ! $CC $flags -I "$ROOT/upstream" "$ROOT/tools/write_dump.c" -lm -o "$BUILD/oracle" 2>"$BUILD/err"; then
        echo "ORACLE BUILD FAIL"; head -5 "$BUILD/err"; fail=1; continue
    fi
    if ! $CC $flags -I "$ROOT/src" -I "$ROOT/upstream" "$ROOT/tools/write_dump.c" -lm -o "$BUILD/cand" 2>"$BUILD/err"; then
        echo "BUILD FAIL"; head -5 "$BUILD/err"; fail=1; continue
    fi
    ok=1
    for v in "${SUBSET[@]}"; do
        IFS='|' read -r in fmt comp q extra <<< "$v"
        # shellcheck disable=SC2086
        "$BUILD/oracle" "$in" "$fmt" "$comp" "$q" $extra > "$BUILD/o.bin" 2>/dev/null
        # shellcheck disable=SC2086
        "$BUILD/cand"   "$in" "$fmt" "$comp" "$q" $extra > "$BUILD/c.bin" 2>/dev/null
        cmp -s "$BUILD/o.bin" "$BUILD/c.bin" || { ok=0; echo "DIFF $v"; }
    done
    [ "$ok" = 1 ] && echo "OK" || fail=1
done

# C++ compile
printf '%-12s ' "cxx"
if $CC -x c++ -O2 -I "$ROOT/src" -I "$ROOT/upstream" "$ROOT/tools/write_dump.c" -lm -o "$BUILD/cxx" 2>"$BUILD/err"; then echo OK; else echo "BUILD FAIL"; head -5 "$BUILD/err"; fail=1; fi

# Cross-targets (compile-only) via zig cc; skipped if zig is not installed.
if command -v zig >/dev/null 2>&1; then
    for target in aarch64-linux-musl x86_64-windows-gnu aarch64-macos; do
        printf '%-12s ' "zig:$target"
        if $ZIG_CC -O3 -target "$target" -I "$ROOT/src" -I "$ROOT/upstream" -c "$ROOT/tools/write_dump.c" -o "$BUILD/wd_$target.o" 2>"$BUILD/err"; then
            echo OK
        else
            echo "BUILD FAIL"; head -5 "$BUILD/err"; fail=1
        fi
    done
else
    echo "zig          SKIP (zig not on PATH; source scripts/env.sh)"
fi

rm -f "$BUILD"/o.bin "$BUILD"/c.bin
if [ "$fail" -eq 0 ]; then echo "PASS verify-portable"; else echo "FAIL verify-portable"; fi
exit $fail
