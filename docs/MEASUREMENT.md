# Measurement & environment audit

Target: **Intel Core i7-14700F** (Raptor Lake; AVX2 + FMA + BMI2, no AVX-512),
28 threads, WSL2. Host distro Ubuntu 24.04.

## Toolchain (Layer 0.1 audit)

| Tool | Availability | Notes |
|---|---|---|
| gcc | **13.3.0** on PATH | system fallback |
| clang + LLD | **23.1.2** (hermetic, user space) | primary; path set by `scripts/env.sh` |
| zig | **0.16.0** | cross-compilation |
| valgrind / callgrind | **3.22.0** | needs `VALGRIND_LIB` (set by `scripts/env.sh`) |
| llvm-mca / llvm-bolt | present in the LLVM tarball | available |
| ispc | 1.31.0 | unused (C intrinsics / SSE2 sufficed) |
| `perf` | **absent** (WSL2, no PMU) | callgrind is the fallback |

The toolchain lives at `/home/armando/c-opt/toolchains` and is shared with the
sibling `stb-image-opt` fork. `scripts/env.sh` puts it on `PATH`, exports the
vendored ICU 70 for `ld.lld`, and sets `VALGRIND_LIB`.

## Clock / units

- Throughput is reported in **nanoseconds per encoded pixel** (min of several
  repeats, pinned with `taskset`). **Ratios only** are used for claims.
- `rdtsc` ticks are deliberately **not** reported as "cycles": on this host the
  invariant TSC is not the core clock, so tick counts understate core cycles
  (the failure documented in the strategy's qoi case). `kernbench` likewise
  reports ns, not cycles.
- Sub-~3% per-row differences are treated as noise; runs are load-sensitive.

## Corpora

Two independent inputs:

1. **Generated pixels** (`tools/gen.h`), deterministic on every platform:
   `grad` (smooth), `plasma` (textured/photographic-like), `random`
   (incompressible worst case), `flat`. Dimensions include edge cases
   (1x1, 1x7, 7x1, 3x5, 17x33, ...).
2. **Real images** in `corpus/` (reused from `stb-image-opt`; the same
   deterministic generator) plus `upstream/tests/pngsuite`. These are decoded
   to pixels with the pristine `stb_image.h` and re-encoded.

The writer is judged on *encode* time; the input pixels are produced once,
outside the timed region.

## Correctness definition (important for an encoder)

- **exact tier**: candidate output is **byte-identical** to the oracle for the
  same input and parameters. This is what `harness/diff.sh` enforces over the
  full format/comp/quality/filter/stride/flip matrix.
- **fast tier**: opt-in (`-ffast-math`); lossless formats must round-trip
  pixel-identically, JPEG must stay within a published bound. Not the default.

The recommended exact flags `-O3 -march=x86-64-v2 -ffp-contract=off` were
verified byte-exact against the oracle built at `-O2` across the whole matrix
(`make verify`). `-march=x86-64-v3 -ffp-contract=off` is also byte-exact
(`make verify-portable`).

## Measurement caveats found on this host

1. **Plumbing-bound writers time noisily.** For BMP/TGA/HDR the per-byte output
   callback dominates, and code-layout changes can swing a row by tens of
   percent even when the hot assembly is byte-identical (observed: the same
   header+flags measured 1.19 and 1.76 ns/px for BMP in two builds). Such rows
   are not used to judge a change; PNG/JPEG compute is the signal. Where a
   plumbing row is reported it is flagged as layout-sensitive.
2. **gprof is not used** (the strategy documents its 39%-vs-7% misattribution);
   hotspots come from callgrind, cross-checked with isolated `kernbench`.
3. **No `perf`** (no PMU under WSL2), so AutoFDO/BOLT are out of reach;
   `llvm-mca`/callgrind are the available ladder rungs.

## PGO

`bench-vs-upstream` uses **held-out** training: the profile is trained on a
training set disjoint from the measured rows (`harness/bench.sh` `HELDOUT`).
Held-out geomean **+62.7%** vs in-sample **+58.5%** (both well above the ~+50%
no-PGO result), so generalization is real. The held-out number is the one
reported in the README; run-to-run variation is a few percent.
