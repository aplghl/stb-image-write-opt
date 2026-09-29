# PORT_STATUS — changed functions and provenance

Oracle: `upstream/stb_image_write.h` v1.16 (`nothings/stb` @ `2c980bb`),
sha256 `cbd5f0ad7a9cf4468affb36354a1d2338034f2c12473cf1a8e32053cb6914a05`.
Never edited. Candidate: `src/stb_image_write.h` (only file modified, +95 lines).

| function / region | status | change | byte-exact gate |
|---|---|---|---|
| `stbiw__zlib_countm` | **optimized** | SSE2 16-byte compare + `movemask`/`ctz`; scalar fallback under `STBIW_NO_SIMD` / non-SSE2 | `diff.sh` 9,652; `kernbench` compressed_bytes identical |
| `stbiw__zlib_huff` / `huffb` macros | **optimized** | precomputed `stbiw__huffcode` / `stbiw__huffbits` tables replace the `stbiw__zlib_bitrev` loop | `diff.sh` |
| length/distance code selection | **optimized** | binary search of `lengthc`/`distc` (same `j`) | `diff.sh` |
| `stbiw__zlib_bitrev` | **removed** | replaced by tables (`huffcode`, `rev5`) | `diff.sh` |
| `stbi_zlib_compress` (other) | untouched | — | — |
| PNG filters, CRC32, JPEG DCT, BMP/TGA/HDR | untouched | — | oracle-identical |

## Provenance ledger

- Phase 2 hotspots: `build/cg4.txt` (callgrind, `plasma_512.png` PNG),
  `build/cg_jpg2.txt` (JPEG). Generator: `callgrind` 3.22.0; note that
  `callgrind_annotate` reports only one top function on this host, so per-line
  cost was read from the auto-annotated source.
- Phase 3 kernel isolation: `results/kernels.csv` via `make kernels`
  (`bench/kernbench.c`, SSE2 vs `-DSTBIW_NO_SIMD`).
- Headline: `results/summary.csv` via `make bench-vs-upstream` (held-out PGO).
- Downstream: `results/consumer.csv` via `make consumer`.
- All correctness gates: `make verify` (9,652 bit-exact + ABI), `make
  verify-portable`, `make sanitize` (1,004 inputs), `make nonvacuous`
  (corrupted candidate fails 2,284/8,308).

## Oracle-hash check

```
sha256sum upstream/stb_image_write.h
# cbd5f0ad7a9cf4468affb36354a1d2338034f2c12473cf1a8e32053cb6914a05
```
Also enforced in CI (`.github/workflows/ci.yml`, job `oracle-integrity`).
