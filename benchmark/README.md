# Cregit performance study

This directory contains the reproducible harness used to locate Cregit's
pipeline bottlenecks. It deliberately separates whole-pipeline timing from
language-specific profiling.

## Corpus

`repositories.tsv` pins three C repositories at exact commits. The corpus is
ordered by historical workload size:

| Repository | Commits | Current `.c`/`.h` files | Historical `.c`/`.h` blobs |
|---|---:|---:|---:|
| libuv | 5,743 | 369 | 12,198 |
| libgit2 | 16,450 | 1,190 | 32,420 |
| curl | 39,532 | 1,017 | 65,069 |

Counts come from `inventory_repo.sh` at the revisions in `repositories.tsv`.
The largest matching blob in this corpus is below 600 KiB, so individual blob
materialization does not put pressure on the benchmark machine's 11 GiB of
RAM.

## Run the baseline

Build the required artifacts first, then run the matrix from the repository
root inside `devenv shell`:

```sh
./benchmark/run_matrix.sh \
  ./benchmark/repositories.tsv \
  ../cregit-performance
```

The runner refuses to overwrite an existing result directory. Set
`REPETITIONS=3` to collect repeated clean runs and let `plot_results.py` use
the per-stage median. Network clone time is recorded but excluded from the
computational wall-clock chart.

Each run records:

- exact repository revision and file mask in `manifest.txt`;
- wall-clock, user CPU, system CPU, CPU percentage, peak RSS, page faults,
  filesystem I/O, and exit status in `metrics.csv`;
- repository workload characteristics in `inventory.csv`;
- the complete command log in `pipeline.log`.

`plot_results.py` produces a stacked wall-clock chart, a top-five bottleneck
chart, and a ranked CSV below the result root's `charts/` directory.

## Compare blobExec schedulers

The opt-in two-pass scheduler can be selected for the full matrix with:

```sh
BLOBEXEC_STRATEGY=prepare-first ./benchmark/run_matrix.sh \
  ./benchmark/repositories.tsv \
  ../cregit-performance-prepare-first
```

The controlled A/B results collected during development are recorded in
`prepare_first_results.csv`. Regenerate their charts with:

```sh
./benchmark/plot_prepare_first.py \
  ./benchmark/prepare_first_results.csv \
  ./benchmark/charts
```

See `REPORT.md` for the profiler findings, correctness checks, complexity,
trade-offs, and the next proposed optimization target.

## Profile a selected stage

After the baseline identifies a stage, collect a separate `perf` recording:

```sh
./benchmark/profile_stage.sh \
  blobexec \
  libuv \
  https://github.com/libuv/libuv.git \
  f87c8e4f70f234b952d9c47b15fb567f78e5f399 \
  https://github.com/libuv/libuv/commit/ \
  ../cregit-profile-libuv-blobexec \
  ../cregit-profiles
```

The profile run is separate from the baseline because sampling changes the
runtime. `render_perf.sh` turns `perf.data` into a textual report, folded
stacks, and an SVG flame graph using Inferno. `perf`, Inferno, `strace`, and
Devel::NYTProf are part of `devenv.nix`; Java Flight Recorder is provided by
the pinned JDK 21.

For safety, `render_perf.sh` refuses inputs larger than 1 GiB by default.
Whole-tree DWARF recordings can grow rapidly when a stage starts thousands of
short-lived processes, and rendering a multi-gigabyte recording can exhaust a
memory-constrained WSL instance. Collect a bounded representative profile
instead of raising the limit on such machines.

## Interpretation rules

- Do not compare the current JGit/SQLite `blobExec` with old BFG-generated
  artifact logs as if they were the same implementation.
- Do not combine `git gc` with history rewriting; both are timed separately.
- A successful run must produce zero per-file blame and pretty-print errors.
- Builds, dependency downloads, and network time are not optimization targets.
- Profile data is used to explain a baseline bottleneck, not as a substitute
  for wall-clock measurements.
