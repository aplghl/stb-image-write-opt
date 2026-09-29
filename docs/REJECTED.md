# Rejected / not-taken experiments (measured)

Everything here was tried or considered and is recorded so it is not retried
blindly. Numbers are on the i7-14700F host, same-flag A/B where applicable.

## Rejected

- **Word-at-a-time `stbiw__zlib_countm` without a scalar prologue.**
  Comparing 8 bytes/iteration via four 32-bit `memcpy` loads and re-scanning the
  tail hurt short-match (textured/photo) input: `plasma_512.png` PNG regressed
  ~4-5% (0.95x) while smooth images gained up to 1.36x. Net +1.4% geomean, not
  worth it. The shipped version compares **16 bytes with baseline SSE2** and
  locates the first mismatch with `movemask`+`ctz`, which is fast for *every*
  match length (1.41 ns/call flat vs 4.6 ns scalar).
- **Fixed-Huffman code tables** (`stbiw__huffcode`/`huffbits`) measured roughly
  **neutral** overall, but help literal-heavy/incompressible input
  (`gen:random` PNG +9%) and remove the per-symbol `stbiw__zlib_bitrev` branch.
  Kept because it is a strict simplification, but do not expect a large win.
- **`-march=x86-64-v3` as the *default* build.** It accelerates the float JPEG
  encoder (5.47 -> 4.06 ns/px on `plasma_512.png`) but emits AVX2/FMA
  instructions everywhere, so it is **not drop-in** for pre-Haswell CPUs. The
  default stays `-march=x86-64-v2`; `-v3` is verified byte-exact and can be
  opted into. Runtime AVX2 dispatch for the JPEG core is left on the table.
- **`STBI_WRITE_NO_STDIO` portability config.** Not testable with `write_dump`:
  upstream defines `stbi_write_hdr_to_func` only inside the `!NO_STDIO` block
  (header line ~812), so the *oracle* itself fails to link. Pre-existing; the
  oracle is not edited. Removed from `harness/portable.sh`.
- **`perf`-based AutoFDO / BOLT.** Unavailable under WSL2 (no PMU). Not
  attempted; callgrind + PGO carry the measurement instead.

## Not taken (remaining headroom)

- **Hash-table allocation churn.** `stbi_zlib_compress` builds 16384 per-bucket
  stretchy buffers and reallocs them (~5% of instructions). Replacing them with
  a flat arena/linked list could help but must reproduce the exact
  candidate-set, order and `2*quality` pruning to stay byte-exact — deferred.
- **PNG row-filter fusion / SIMD.** `stbiw__encode_png_line` runs five filters
  per row plus an entropy estimate (~11% of PNG encode incl. `stbiw__paeth`).
  The sibling `stb_image` measured AVX2 unfiltering as slower (0.44-0.99x), so
  this is high-risk; not attempted.
- **Runtime-dispatched AVX2 JPEG core (DCT + RGB->YCbCr).** Would capture the
  `-v3` JPEG gain while staying drop-in, but float DCT byte-exactness under
  hand-written AVX2 is nontrivial and the compile-time `-v3` build is already
  byte-exact. Deferred.
