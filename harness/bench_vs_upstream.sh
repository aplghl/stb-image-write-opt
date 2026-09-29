#!/bin/bash
# Head-to-head: stock upstream (-O2) vs the optimized fork. Writes
# results/upstream_o2.csv, results/fork.csv and results/summary.csv.
#
# usage: harness/bench_vs_upstream.sh
#   CC, BUDGET, REPEATS, PIN   knobs (see harness/bench.sh)
#   CAND_FLAGS                 candidate flags (default -O3 -march=x86-64-v2 -ffp-contract=off)
#   PGO=1                      two-pass PGO for the candidate (in-sample vectors)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC=${CC:-clang}
export CC
BUDGET=${BUDGET:-0.1}
REPEATS=${REPEATS:-5}
PIN=${PIN:-2}
CAND_FLAGS=${CAND_FLAGS:-"-O3 -march=x86-64-v2 -ffp-contract=off"}
CAND_NAME=${CAND_NAME:-fork}
PGO=${PGO:-0}
TRAIN_SET=${TRAIN_SET:-heldout}
export BUDGET REPEATS PIN TRAIN_SET

if [ "$PGO" = 1 ]; then
    echo "### candidate: fork + PGO (in-sample training)"
    PGO_DIR="$ROOT/build/pgo_vs" bash "$ROOT/harness/bench.sh" "$CAND_NAME" src $CAND_FLAGS
else
    echo "### candidate: fork"
    bash "$ROOT/harness/bench.sh" "$CAND_NAME" src $CAND_FLAGS
fi

echo "### baseline: upstream -O2"
bash "$ROOT/harness/bench.sh" upstream_o2 upstream -O2

python3 - "$ROOT" "$CAND_NAME" <<'PY'
import csv, math, sys, os
root, cand = sys.argv[1], sys.argv[2]
def load(p):
    d = {}
    for r in csv.DictReader(open(p)):
        key = (r.get("input"), r.get("format"), r.get("comp"), r.get("quality"))
        try: d[key] = (float(r["ns_per_pixel"]), r)
        except Exception: pass
    return d
up = load(os.path.join(root, "results/upstream_o2.csv"))
fk = load(os.path.join(root, "results", cand + ".csv"))
rows, ratios = [], []
for k in up:
    if k in fk and fk[k][0] > 0:
        r = up[k][0] / fk[k][0]
        rows.append((k, up[k][0], fk[k][0], r)); ratios.append(r)
rows.sort(key=lambda x: x[3])
print(f"\n{'input/format/c/q':58s} {'upstream':>10s} {'fork':>10s} {'speedup':>8s}")
for k, a, b, r in rows:
    label = f"{k[0]}/{k[1]}/c{k[2]}/q{k[3]}"
    print(f"{label:58s} {a:10.4f} {b:10.4f} {r:7.3f}x")
gm = math.exp(sum(math.log(r) for r in ratios) / len(ratios)) if ratios else 0.0
print(f"\ngeomean speedup over {len(ratios)} rows: {gm:.4f}x  ({(gm-1)*100:+.1f}%)")
with open(os.path.join(root, "results/summary.csv"), "w") as out:
    out.write("input,format,comp,quality,upstream_ns_per_pixel,fork_ns_per_pixel,speedup\n")
    for k, a, b, r in rows:
        out.write(f"{k[0]},{k[1]},{k[2]},{k[3]},{a},{b},{r}\n")
    out.write(f"GEOMEAN,,,,,,{gm}\n")
PY
