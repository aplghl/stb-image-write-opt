# stb-image-write-opt convenience targets. Source scripts/env.sh first so the
# hermetic clang toolchain is on PATH (or override CC).
#
# The oracle is ALWAYS the pristine upstream header; only src/ is modified.

ROOT := $(CURDIR)
ifeq ($(origin CC),default)
CC := $(shell command -v clang 2>/dev/null || command -v gcc 2>/dev/null || echo cc)
endif
export CC

# Recommended exact build (byte-identical; see docs/MEASUREMENT.md).
EXACT_FLAGS ?= -O3 -march=x86-64-v2 -ffp-contract=off
FAST_FLAGS  ?= -O3 -march=x86-64-v2 -ffast-math
PORTABLE_FLAGS ?= -O2

.PHONY: all verify verify-portable abi sanitize nonvacuous bench bench-vs-upstream \
        consumer kernels clean help

all: verify

## Full correctness gate: byte-exact vs the pristine oracle + ABI check.
verify:
	bash harness/diff.sh $(EXACT_FLAGS)
	bash harness/abi.sh

## Portability matrix: scalar / no-simd / arch variants / C++ / cross-targets.
verify-portable:
	bash harness/portable.sh

## ABI/symbol exactness vs upstream.
abi:
	bash harness/abi.sh

## ASan+UBSan over the encode matrix (incl. padded strides).
sanitize:
	bash harness/sanitize.sh

## Prove the differential suite is non-vacuous (corrupt-on-purpose fails).
nonvacuous:
	bash harness/nonvacuous.sh

## Throughput of the candidate (writes results/fork.csv).
bench:
	bash harness/bench.sh fork src $(EXACT_FLAGS)

## Head-to-head vs stock upstream -O2, held-out PGO -> results/summary.csv.
bench-vs-upstream:
	PGO=1 TRAIN_SET=heldout bash harness/bench_vs_upstream.sh

## Downstream consumer program vs the prebuilt library -> results/consumer.csv.
consumer:
	PGO=1 bash harness/consumer/run.sh

## Per-kernel microbenchmarks (SSE2 vs scalar) -> results/kernels.csv.
kernels:
	bash harness/kernbench.sh

clean:
	rm -rf build gmon.out .zig-cache zig-out

help:
	@grep -E '^## ' Makefile | sed 's/^## //'
