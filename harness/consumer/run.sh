#!/bin/bash
# Build and run the downstream consumer against the stock header and against
# the prebuilt fork library, then report the speedup. Commits the delta to
# results/consumer.csv.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/build/consumer"; mkdir -p "$BUILD" "$ROOT/results"
CC=${CC:-clang}
PIN=${PIN:-3}
PGO=${PGO:-0}

echo "== consumer: stock upstream -O2 =="
$CC -O2 -I "$ROOT/upstream" -DSTB_IMAGE_WRITE_IMPLEMENTATION \
    "$ROOT/harness/consumer/consumer.c" -lm -o "$BUILD/stock"

echo "== consumer: fork (headers/link)" >&2
if [ "$PGO" = 1 ]; then
    PGO=1 bash "$ROOT/scripts/build_opt.sh" exact "$ROOT/build/lib_consumer" >/dev/null
else
    bash "$ROOT/scripts/build_opt.sh" exact "$ROOT/build/lib_consumer" >/dev/null
fi
$CC -O3 -march=x86-64-v2 -ffp-contract=off -I "$ROOT/src" \
    "$ROOT/harness/consumer/consumer.c" \
    "$ROOT/build/lib_consumer/libstb_image_write_opt.a" -lm -o "$BUILD/fork"

python3 - "$ROOT" "$BUILD/stock" "$BUILD/fork" "$PIN" <<'PY'
import subprocess, sys, csv, math, os
root, stock, fork, pin = sys.argv[1:5]
def run(b):
    out = subprocess.run(["taskset","-c",pin,b], capture_output=True, text=True).stdout.strip().splitlines()
    return {r.split(",")[0]: float(r.split(",")[1]) for r in out}
s, f = run(stock), run(fork)
rows = []
print(f"\n{'format':8s} {'stock ns/px':>12s} {'fork ns/px':>12s} {'speedup':>8s}")
for k in ["png","jpg"]:
    r = s[k]/f[k]; rows.append((k,s[k],f[k],r))
    print(f"{k:8s} {s[k]:12.4f} {f[k]:12.4f} {r:7.3f}x")
gm = math.exp(sum(math.log(x[3]) for x in rows)/len(rows))
print(f"\nconsumer geomean: {gm:.4f}x ({(gm-1)*100:+.1f}%)")
with open(os.path.join(root,"results/consumer.csv"),"w") as o:
    o.write("format,stock_ns_per_pixel,fork_ns_per_pixel,speedup\n")
    for k,a,b,r in rows: o.write(f"{k},{a},{b},{r}\n")
    o.write(f"GEOMEAN,,,{gm}\n")
PY
