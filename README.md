# stb-image-write-opt

A performance fork of [stb_image_write](https://github.com/nothings/stb)
(`stb_image_write.h` v1.16) that is a **byte-identical drop-in replacement**.
The PNG deflate match kernel is accelerated with baseline SSE2, the fixed
Huffman codes are precomputed, and the recommended build also enables the
compiler's auto-vectorization of the JPEG encoder — all verified to produce
**exactly the same output bytes** as upstream.

- **Upstream base:** `nothings/stb` @ `2c980bb` (`stb_image_write.h` v1.16),
  vendored in `upstream/` as the pristine oracle. `sha256` of the oracle header:
  `cbd5f0ad7a9cf4468affb36354a1d2338034f2c12473cf1a8e32053cb6914a05`.
- **License:** MIT OR Unlicense, same as upstream.
- **Scope:** `stb_image_write.h` only (the encode/write side).
- **Status:** exact tier is byte-identical to upstream; the SSE2 path is
  baseline on x86-64 (no runtime dispatch needed) and other targets fall back to
  scalar.

Only **`src/stb_image_write.h`** is modified. The public API, structs, ABI and
default behavior are unchanged (16 exported symbols, verified by `make abi`).

## Results

Stock upstream is compiled the way consumers compile it (`-O2`). The fork is
compiled with `-O3 -march=x86-64-v2 -ffp-contract=off` plus **held-out** PGO
(trained on inputs disjoint from the measured rows). Intel i7-14700F, clang
23.1.2, WSL2. Reproduce with `make bench-vs-upstream`.

| workload | speedup vs upstream `-O2` |
| --- | --- |
| Mixed suite (`results/summary.csv`) | **+62.7% geomean** (held-out PGO; ~+50% no PGO) |
| PNG encode | **1.62–2.15×** |
| JPEG encode | **1.63–2.04×** |
| `stbiw__zlib_countm` (isolated, SSE2 vs scalar) | **~3.3×** |
| deflate kernel (isolated, SSE2 vs scalar) | **3.4×** (0.43 vs 1.47 ns/byte) |
| downstream consumer (`make consumer`) | PNG **1.90×**, JPEG **1.17×** |

Run-to-run variation is a few percent; the committed `results/summary.csv` is
the artifact of record.

The exact build is **byte-identical** to upstream over the full matrix (~9,600
checks: 5 formats × comp 1–4 × quality/filter/stride/RLE/flip toggles ×
generated and real images), on scalar (`-DSTBIW_NO_SIMD`), `-march=x86-64-v2`
and `-march=x86-64-v3`, and with clang, gcc and `zig cc`. See
`docs/MEASUREMENT.md` for the variance caveats.

## What changed

Three changes in `src/stb_image_write.h`, all byte-exact:

1. **SSE2 match kernel** (`stbiw__zlib_countm`). The DEFLATE match-length scan
   was a byte-at-a-time loop and was ~30% of PNG encode time. It now compares
   16 bytes per iteration with baseline SSE2 and locates the first differing
   byte via `movemask`+`ctz`. SSE2 is guaranteed on x86-64, so there is **no
   runtime dispatch and no new dependency**; non-SSE2 targets (and
   `-DSTBIW_NO_SIMD`) use the original scalar loop.

2. **Precomputed fixed-Huffman codes.** DEFLATE's fixed codes are reversed
   bit-for-bit on emit; the tables `stbiw__huffcode`/`stbiw__huffbits` store the
   already-reversed code so the per-symbol `stbiw__zlib_bitrev` loop is gone.
   Helps literal-heavy (incompressible) input.

3. **Binary-searched length/distance code tables.** The per-match linear scans
   over `lengthc`/`distc` became binary searches with identical results.

The recommended `-march=x86-64-v2` additionally lets the compiler
auto-vectorize the scalar float JPEG encoder; `-ffp-contract=off` keeps it
byte-exact.

## Usage

### Option 1 — drop-in header

Replace your `stb_image_write.h` with `src/stb_image_write.h`. Nothing else
changes:

```c
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
```

You get the SSE2 and table wins immediately. For the full gain, compile with
`-O3 -march=x86-64-v2 -ffp-contract=off`, or use Option 2.

### Option 2 — prebuilt static library

```sh
# byte-identical exact build
scripts/build_opt.sh exact
# with multi-workload PGO
PGO=1 scripts/build_opt.sh exact

# or via Zig (also supports cross-targets)
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-musl
```

Then include the header **without** `STB_IMAGE_WRITE_IMPLEMENTATION` and link
`build/lib_exact/libstb_image_write_opt.a` (or
`zig-out/lib/libstb-image-write-opt.a`):

```c
#include "stb_image_write.h"   /* declarations only */
/* ... stbi_write_png(...), stbi_write_jpg(...) ... */
```

## Verifying

The harness needs only a C compiler and the committed corpus.

```sh
make verify             # byte-exact differential + ABI check
make verify-portable    # scalar / no-simd / v2 / v3 / C++ / cross-targets
make sanitize           # ASan+UBSan over the encode matrix
make nonvacuous         # corrupt-on-purpose must FAIL the suite
make kernels            # isolated deflate kernels -> results/kernels.csv
make bench-vs-upstream  # held-out PGO vs upstream -O2 -> results/summary.csv
make consumer           # downstream integration benchmark -> results/consumer.csv
```

`upstream/` is the pristine oracle; the candidate is always `src/`.

## Compatibility

| configuration | result |
| --- | --- |
| x86-64 (SSE2 baseline) | byte-exact, uses SSE2 match kernel |
| non-x86 (aarch64, ...) | byte-exact, scalar fallback |
| `-DSTBIW_NO_SIMD` | byte-exact, scalar fallback |
| `-march=x86-64-v2` / `-march=x86-64-v3` | byte-exact |
| C and C++ | compiles clean |
| gcc, clang, `zig cc` | byte-exact |
| aarch64-linux-musl, x86_64-windows-gnu, aarch64-macos | cross-compiles |

## Repository layout

```
src/stb_image_write.h    optimized header (the fork; only file modified)
upstream/                pristine nothings/stb (oracle, never edited)
lib/stb_image_write.c    TU for the prebuilt static library
tools/write_dump.c       differential encoder (dumps exact output bytes)
tools/gen.h              deterministic pixel generators
bench/bench.c            encode throughput
bench/kernbench.c        isolated kernel microbenchmarks
harness/                 diff, portable, sanitize, nonvacuous, abi, bench*, kernbench, consumer/
scripts/                 env.sh, build_opt.sh
build.zig Makefile       multi-target / convenience targets
docs/                    MEASUREMENT.md, REJECTED.md
results/                 benchmark CSVs (see results/README.md)
```

## License

MIT OR Unlicense, same as upstream. Based on
[stb](https://github.com/nothings/stb) by Sean Barrett and contributors. This is
an unofficial fork and is **not endorsed by the upstream author**.
