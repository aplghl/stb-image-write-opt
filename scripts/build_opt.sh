#!/bin/bash
# Build the drop-in static library with the recommended flags, optionally with
# multi-workload PGO. The public API/ABI is the original stb_image_write one.
#
# usage: scripts/build_opt.sh [exact|fast] [outdir]
#   exact (default): byte-identical to upstream; -ffp-contract=off
#   fast           : allows reassociation (-ffast-math), not byte-exact
#
# env: CC (default clang), PGO=1 to train, ARCH (default x86-64-v2)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-exact}
OUT=${2:-"$ROOT/build/lib_$MODE"}
CC=${CC:-clang}
ARCH=${ARCH:-x86-64-v2}
PGO=${PGO:-0}

case "$MODE" in
    exact) FPF="-ffp-contract=off" ;;
    fast)  FPF="-ffast-math" ;;
    *) echo "unknown mode: $MODE (expected exact|fast)"; exit 2 ;;
esac
FLAGS="-O3 -march=$ARCH $FPF"
mkdir -p "$OUT"

if [ "$PGO" = "1" ]; then
    PROF="$ROOT/build/pgo_lib_$MODE"
    rm -rf "$PROF" && mkdir -p "$PROF"
    # Pass 1: instrument via the write_dump training driver (same writer code).
    $CC $FLAGS -fprofile-generate="$PROF" -I "$ROOT/src" -I "$ROOT/upstream" \
        "$ROOT/tools/write_dump.c" -lm -o "$OUT/train"
    # Held-out-ish training: varied images/dimensions/formats, not the benchmark.
    train_one() { "$OUT/train" "$@" >/dev/null 2>&1 || true; }
    for f in "$ROOT"/corpus/*.png "$ROOT"/corpus/*.ppm "$ROOT"/corpus/*.bmp \
             "$ROOT"/upstream/tests/pngsuite/primary/*.png; do
        [ -e "$f" ] || continue
        train_one "$f" png 3 8
        train_one "$f" jpg 3 85
        train_one "$f" bmp 3 8
        train_one "$f" tga 4 8
    done
    for d in 128x96 320x240 64x200; do
        for m in plasma grad random; do
            train_one "gen:$m" png 3 8 --dims "$d"
            train_one "gen:$m" jpg 3 80 --dims "$d"
        done
    done
    # Pass 2: rebuild the library object with the merged profile.
    case "$CC" in
      *clang*) llvm-profdata merge -output="$PROF/default.profdata" "$PROF"/*.profraw
               $CC $FLAGS -fprofile-use="$PROF/default.profdata" -I "$ROOT/src" -c "$ROOT/lib/stb_image_write.c" -o "$OUT/stb_image_write.o" ;;
      *)       $CC $FLAGS -fprofile-use="$PROF" -fprofile-correction -I "$ROOT/src" -c "$ROOT/lib/stb_image_write.c" -o "$OUT/stb_image_write.o" ;;
    esac
    rm -f "$OUT/train"
else
    $CC $FLAGS -I "$ROOT/src" -c "$ROOT/lib/stb_image_write.c" -o "$OUT/stb_image_write.o"
fi

ar rcs "$OUT/libstb_image_write_opt.a" "$OUT/stb_image_write.o"
cp "$ROOT/src/stb_image_write.h" "$OUT/stb_image_write.h"
echo "built $OUT/libstb_image_write_opt.a (mode=$MODE arch=$ARCH pgo=$PGO)"
