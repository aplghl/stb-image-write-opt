# Changelog

## v1.0.0

First release. Fork of `nothings/stb` `stb_image_write.h` v1.16 (`2c980bb`).

### Added
- Runtime-free SSE2 DEFLATE match kernel (`stbiw__zlib_countm`), byte-exact,
  with a scalar fallback on non-SSE2 targets and under `-DSTBIW_NO_SIMD`.
- Precomputed fixed-Huffman code tables (`stbiw__huffcode` / `stbiw__huffbits`)
  and a 5-bit distance reverse table, replacing the per-symbol bit-reversal.
- Binary-searched length/distance code tables.
- `build.zig` static library + release workflow (gnu/musl/arm64/windows).
- Bit-exact differential harness over 5 formats x comp x quality/filter/stride/
  RLE/flip, sanitizer gate, portability matrix, ABI check, non-vacuous proof,
  isolated kernel benchmark, and a downstream consumer benchmark.

### Results (Intel i7-14700F, clang 23.1.2, held-out PGO)
- Mixed-suite geomean **+62.7%** vs upstream `-O2` (~+50% without PGO).
- PNG encode **1.62-2.15x**; JPEG encode **1.63-2.04x**.
- Isolated `countm` **1.41 vs 4.6 ns/call**; deflate **0.43 vs 1.47 ns/byte**.
- Byte-identical output on ~9,600 differential checks and every tested
  configuration; ABI exports unchanged.

### Notes
- BMP/TGA/HDR timings are plumbing-bound and layout-sensitive; not claimed.
- `-march=x86-64-v3` is byte-exact but not the default (not drop-in on
  pre-Haswell CPUs). Runtime AVX2 dispatch for the JPEG core is future work.
