#!/bin/bash
# Encode throughput benchmark against a chosen header dir. Writes
# results/<name>.csv and prints the geomean ns/pixel.
#
# usage: harness/bench.sh <name> <header_dir> [flags...]
#   header_dir : upstream | src   (the stb_image_write.h under test)
#   PGO_DIR=/abs/dir            two-pass PGO for this build
#   BUDGET, REPEATS, PIN, CC    knobs
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:?name required}
HDR=${2:?header dir required}
shift 2
FLAGS=${*:-"-O2"}
CC=${CC:-clang}
BUDGET=${BUDGET:-0.1}
REPEATS=${REPEATS:-5}
PIN=${PIN:-2}
PGO_DIR=${PGO_DIR:-""}

BUILD="$ROOT/build"
RES="$ROOT/results"
mkdir -p "$BUILD" "$RES"
BIN="$BUILD/bench_$NAME"

INCS=(-I "$ROOT/$HDR" -I "$ROOT/upstream" -I "$ROOT/tools")
SRC="$ROOT/bench/bench.c"

# Representative writer suite: input|format|comp|quality|extra-opts
VECTORS=(
    "corpus/plasma_512.png|png|3|8|"
    "corpus/plasma_512.png|png|4|8|"
    "corpus/plasma_512.png|png|3|5|"
    "corpus/plasma_512.png|jpg|3|90|"
    "corpus/plasma_512.png|jpg|3|75|"
    "corpus/plasma_512.png|jpg|3|50|"
    "corpus/plasma_512.png|bmp|3|8|"
    "corpus/plasma_512.png|tga|3|8|--rle 1"
    "corpus/plasma_512.png|tga|4|8|--rle 1"
    "corpus/plasma_512.png|hdr|3|8|"
    "corpus/grad_640_480.png|png|3|8|"
    "corpus/grad_640_480_gray.png|png|1|8|"
    "corpus/grad_640_480_rgba.png|png|4|8|"
    "corpus/plasma_512_pal.png|png|3|8|"
    "gen:random|png|3|8|--dims 512x512"
    "gen:grad|png|3|8|--dims 1024x768"
    "gen:plasma|jpg|3|90|--dims 1024x768"
)

# Held-out PGO training set: deliberately disjoint from VECTORS (different
# images, dimensions, formats, qualities) so the reported gain is out-of-sample.
HELDOUT=(
    "corpus/grad_64.png|png|3|8|"
    "corpus/grad_64.png|png|1|5|"
    "corpus/grad_64_rgba.png|png|4|9|"
    "corpus/grad_640_480.png|png|1|8|"
    "corpus/grad_640_480.png|jpg|1|95|"
    "corpus/grad_640_480_gray.png|jpg|1|60|"
    "corpus/grad_640_480.bmp|bmp|3|8|"
    "corpus/grad_640_480.tga|tga|3|8|--rle 0"
    "corpus/grad_640_480.ppm|hdr|3|8|"
    "upstream/tests/pngsuite/primary/basn2c08.png|png|3|8|"
    "upstream/tests/pngsuite/primary/basn6a08.png|png|4|8|"
    "upstream/tests/pngsuite/primary/basn0g16.png|png|1|8|"
    "upstream/tests/pngsuite/primary/basn3p08.png|png|3|8|"
    "gen:plasma|png|3|9|--dims 320x240"
    "gen:plasma|jpg|3|80|--dims 320x240"
    "gen:random|png|4|5|--dims 300x200"
    "gen:grad|jpg|3|70|--dims 400x300"
    "gen:grad|tga|4|8|--rle 1"
)

build() {
    if [ -n "$PGO_DIR" ]; then
        rm -rf "$PGO_DIR" && mkdir -p "$PGO_DIR"
        $CC $FLAGS -ffp-contract=off -fprofile-generate="$PGO_DIR" "${INCS[@]}" "$SRC" -lm -o "$BIN" || exit 1
        local train_list=("${VECTORS[@]}")
        [ "${TRAIN_SET:-heldout}" = "heldout" ] && train_list=("${HELDOUT[@]}")
        for v in "${train_list[@]}"; do
            IFS='|' read -r in fmt comp q extra <<< "$v"
            [ -e "$ROOT/$in" ] || [[ "$in" == gen:* ]] || continue
            taskset -c "$PIN" "$BIN" "$in" "$fmt" "$comp" "$q" 0.01 1 $extra >/dev/null 2>&1
        done
        case "$CC" in
          *clang*)
            llvm-profdata merge -output="$PGO_DIR/default.profdata" "$PGO_DIR"/*.profraw || exit 1
            $CC $FLAGS -ffp-contract=off -fprofile-use="$PGO_DIR/default.profdata" "${INCS[@]}" "$SRC" -lm -o "$BIN" || exit 1 ;;
          *)
            $CC $FLAGS -ffp-contract=off -fprofile-use="$PGO_DIR" -fprofile-correction "${INCS[@]}" "$SRC" -lm -o "$BIN" || exit 1 ;;
        esac
    else
        $CC $FLAGS -ffp-contract=off "${INCS[@]}" "$SRC" -lm -o "$BIN" || exit 1
    fi
}

echo "== bench $NAME: hdr=$HDR flags='$FLAGS' pgo='${PGO_DIR:-none}' =="
build

CSV="$RES/$NAME.csv"
echo "input,format,comp,quality,w,h,bytes,iters,ns_per_encode,ns_per_pixel,Mpixel_per_s" > "$CSV"
for v in "${VECTORS[@]}"; do
    IFS='|' read -r in fmt comp q extra <<< "$v"
    if [[ "$in" != gen:* ]] && [ ! -e "$ROOT/$in" ]; then continue; fi
    taskset -c "$PIN" "$BIN" "$in" "$fmt" "$comp" "$q" "$BUDGET" "$REPEATS" $extra >> "$CSV"
done

python3 - "$NAME" "$CSV" <<'PY'
import csv, sys, math
name, path = sys.argv[1], sys.argv[2]
vals = []
for r in csv.DictReader(open(path)):
    try: vals.append(float(r["ns_per_pixel"]))
    except (KeyError, ValueError): pass
if vals:
    gm = math.exp(sum(math.log(v) for v in vals) / len(vals))
    print(f"{name}: n={len(vals)} mean_ns_per_pixel={sum(vals)/len(vals):.4f} geomean={gm:.4f}")
PY
