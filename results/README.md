# results

Benchmark CSVs from the fork. Timings are machine-specific (Intel i7-14700F,
WSL2, clang 23.1.2) and load-sensitive; rank/ratios are the signal. Correctness
is verified separately (`make verify`, `make verify-portable`, `make sanitize`,
`make nonvacuous`) and is machine-independent.

| file | generator | contents |
| ---- | --------- | -------- |
| `summary.csv` | `make bench-vs-upstream` | **headline**: per-row upstream `-O2` vs fork (`-O3 -march=x86-64-v2 -ffp-contract=off` + held-out PGO) and the geomean |
| `upstream_o2.csv` | `make bench-vs-upstream` | baseline throughput, upstream header at `-O2` |
| `fork.csv` | `make bench-vs-upstream` | fork throughput (held-out PGO) |
| `kernels.csv` | `make kernels` | isolated deflate kernels: `countm` (SSE2 vs scalar) and deflate ns/byte |
| `consumer.csv` | `make consumer` | downstream consumer program (public API, links the prebuilt `.a`) vs stock |

Column notes:

- `summary`/`upstream_o2`/`fork`: `input,format,comp,quality,w,h,bytes,iters,`
  `ns_per_encode,ns_per_pixel,Mpixel_per_s`.
- `kernels`: `variant,kernel,metric,value,unit` (`variant` = sse2 | scalar).
- `consumer`: `format,stock_ns_per_pixel,fork_ns_per_pixel,speedup`.

Key numbers: held-out PGO geomean **+62.7%**; PNG rows **1.62-2.15x**; JPEG rows
**1.63-2.04x**; `countm` **1.41 vs 4.6 ns/call** and deflate **0.43 vs 1.47
ns/byte** (SSE2 vs scalar, byte-identical output); downstream consumer PNG
**1.90x**, JPEG **1.17x**.

> BMP/TGA/HDR rows are plumbing-bound (a per-byte output callback dominates) and
> their timings swing with code layout; do not read a speedup from them. See
> `docs/MEASUREMENT.md` caveat #1.
