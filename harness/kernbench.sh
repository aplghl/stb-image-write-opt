#!/bin/bash
# Isolated deflate-kernel microbenchmarks. Builds kernbench twice (SSE2 vs
# scalar fallback) and writes results/kernels.csv.
#
# usage: harness/kernbench.sh
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"; mkdir -p "$BUILD" "$ROOT/results"
CC=${CC:-clang}
FLAGS=${FLAGS:-"-O3 -march=x86-64-v2 -ffp-contract=off"}
PIN=${PIN:-3}

echo "== kernbench: flags='$FLAGS' =="
$CC $FLAGS -ffp-contract=off -I "$ROOT/src" "$ROOT/bench/kernbench.c" -lm -o "$BUILD/kern_sse2" || exit 1
$CC $FLAGS -DSTBIW_NO_SIMD -ffp-contract=off -I "$ROOT/src" "$ROOT/bench/kernbench.c" -lm -o "$BUILD/kern_scalar" || exit 1

CSV="$ROOT/results/kernels.csv"
echo "variant,kernel,metric,value,unit" > "$CSV"
for v in sse2 scalar; do
    taskset -c "$PIN" "$BUILD/kern_$v" 0.1 7 | tail -n +2 |
    while IFS=, read -r kern metric value unit iters; do
        echo "$v,$kern,$metric,$value,$unit" >> "$CSV"
    done
done

column -s, -t "$CSV"
