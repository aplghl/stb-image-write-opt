#!/bin/bash
# Byte-exact differential test: candidate (src/) vs pristine upstream oracle.
#
# Builds write_dump twice and encodes a deterministic input/parameter matrix:
# every format (png/bmp/tga/hdr/jpg), channel counts 1..4, qualities/filters,
# strides, flip and RLE toggles, over generated pixels and real corpus images.
# Requires byte-identical stdout AND identical exit codes.
#
# The oracle is ALWAYS built with canonical upstream flags (-O2) so any numeric
# change caused by candidate source changes OR candidate flags is caught.
#
# usage: harness/diff.sh [candidate flags...]
#   ORACLE_FLAGS="..."  override oracle flags (default "-O2")
#   CC=clang            compiler (defaults to clang if present, else gcc)
#   FULL=1              also run the larger real-image matrix (default 1)
#   QUIET=1             only print the summary
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"

if [ -z "${CC:-}" ]; then
    if command -v clang >/dev/null 2>&1; then CC=clang; else CC=gcc; fi
fi
export CC

CAND_FLAGS=${CAND_FLAGS:-"-O2"}
[ $# -gt 0 ] && CAND_FLAGS="$*"
ORACLE_FLAGS=${ORACLE_FLAGS:-"-O2"}
QUIET=${QUIET:-0}
FULL=${FULL:-1}
SRC_DIR=${SRC_DIR:-"$ROOT/src"}

echo "== differential: oracle='$ORACLE_FLAGS' candidate='$CAND_FLAGS' cc=$CC src=$SRC_DIR =="

$CC $ORACLE_FLAGS -ffp-contract=off -I "$ROOT/upstream" "$ROOT/tools/write_dump.c" -lm -o "$BUILD/write_oracle" || exit 1
$CC $CAND_FLAGS  -ffp-contract=off -I "$SRC_DIR" -I "$ROOT/upstream" "$ROOT/tools/write_dump.c" -lm -o "$BUILD/write_cand" || exit 1

O="$BUILD/write_oracle"
C="$BUILD/write_cand"
fail=0; n=0; nfail=0

# cmp_case <description> <args...>
cmp_case() {
    local desc=$1; shift
    "$O" "$@" > "$BUILD/_o.bin" 2>/dev/null; local ro=$?
    "$C" "$@" > "$BUILD/_c.bin" 2>/dev/null; local rc=$?
    n=$((n + 1))
    if [ "$ro" != "$rc" ] || ! cmp -s "$BUILD/_o.bin" "$BUILD/_c.bin"; then
        [ "$QUIET" = 1 ] || echo "DIFF [$desc] oracle_rc=$ro cand_rc=$rc: $*"
        fail=1; nfail=$((nfail + 1))
    fi
}

# matrix over one input spec (everything after <input>)
matrix_for() {
    local input=$1; shift
    local opt=("$@")
    local fmt comp q ff rle flip st
    for fmt in png bmp tga hdr jpg; do
        for comp in 1 2 3 4; do
            for flip in 0 1; do
                case $fmt in
                    png)
                        for q in 5 8 9; do
                            for ff in -1 0 1 2 3 4; do
                                cmp_case "png c$comp q$q ff$ff f$flip" "$input" png "$comp" "$q" "${opt[@]}" --force-filter "$ff" --flip "$flip"
                            done
                            if [ "${DO_STRIDE:-1}" = 1 ]; then
                                for st in 0 1 7; do
                                    cmp_case "png c$comp q$q stride+$st f$flip" "$input" png "$comp" "$q" "${opt[@]}" --stride $(( ${W_OVERRIDE:-64} * comp + st )) --flip "$flip"
                                done
                            fi
                        done
                        ;;
                    bmp) cmp_case "bmp c$comp f$flip" "$input" bmp "$comp" 8 "${opt[@]}" --flip "$flip" ;;
                    tga) for rle in 0 1; do cmp_case "tga c$comp rle$rle f$flip" "$input" tga "$comp" 8 "${opt[@]}" --rle "$rle" --flip "$flip"; done ;;
                    hdr) cmp_case "hdr c$comp f$flip" "$input" hdr "$comp" 8 "${opt[@]}" --flip "$flip" ;;
                    jpg) for q in 1 10 50 90 95 100; do cmp_case "jpg c$comp q$q f$flip" "$input" jpg "$comp" "$q" "${opt[@]}" --flip "$flip"; done ;;
                esac
            done
        done
    done
}

# --- generated pixel inputs (deterministic, no files) ---
for dims in 1x1 1x7 7x1 3x5 16x16 17x33 64x48; do
    W_OVERRIDE=${dims%x*}
    for mode in grad plasma random flat; do
        matrix_for "gen:$mode" --dims "$dims"
    done
done

# --- real corpus images (photographic / indexed / grayscale content) ---
if [ "$FULL" = 1 ]; then
    SUB="corpus/plasma_512.png corpus/grad_640_480.png corpus/grad_640_480_gray.png \
         corpus/grad_640_480_rgba.png corpus/plasma_512_pal.png \
         upstream/tests/pngsuite/primary/basn2c16.png upstream/tests/pngsuite/primary/basn0g01.png"
    DO_STRIDE=0
    for rel in $SUB; do
        [ -e "$ROOT/$rel" ] || continue
        # Real images are packed, so no padded-stride sweep (write_dump only pads
        # for generated inputs where it knows the padded size).
        matrix_for "$ROOT/$rel"
    done
    DO_STRIDE=1
fi

# --- channel-count coercion on real image data (decode to N channels, encode N) ---
if [ -e "$ROOT/corpus/plasma_512.png" ]; then
    for ic in 1 2 3 4; do
        for fmt in png jpg bmp tga hdr; do
            cmp_case "incomp$ic $fmt" "$ROOT/corpus/plasma_512.png" "$fmt" "$ic" 90 --incomp "$ic"
        done
    done
fi

rm -f "$BUILD/_o.bin" "$BUILD/_c.bin"
if [ "$fail" -eq 0 ]; then
    echo "PASS: $n checks byte-exact"
else
    echo "FAIL: $nfail of $n checks diverged"
fi
exit $fail
