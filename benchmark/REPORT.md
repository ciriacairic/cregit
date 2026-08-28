# Cregit pipeline performance report

## Result

`blobExec` is the dominant pipeline stage, accounting for about 90% of the
measured compute wall time in the completed medium repositories. Its current
commit-local scheduler leaves most workers idle because it waits at every
commit boundary. The experimental `--prepare-first` scheduler removes that
barrier by discovering all missing `(blob, path)` tasks, preparing them in a
bounded global queue, and then rebuilding commits in a second pass.

The change reduced `blobExec` wall time in every measured repository:

| Repository | Workload | Commit-local | Prepare-first | Speedup | Wall reduction | Peak RSS change |
|---|---:|---:|---:|---:|---:|---:|
| jq | 1,938 commits / 1,890 tasks | 246.84 s | 130.38 s | 1.89x | 47.2% | -0.2% |
| libuv | 5,743 commits / 12,418 tasks | 1,045.03 s | 611.33 s | 1.71x | 41.5% | +2.1% |
| libgit2 | 16,450 commits / 33,735 tasks | 3,826.82 s | 2,891.41 s | 1.32x | 24.4% | -7.5% |

The corresponding charts are
[`prepare_first_wall.svg`](charts/prepare_first_wall.svg) and
[`prepare_first_phases.svg`](charts/prepare_first_phases.svg). Raw values are
in [`prepare_first_results.csv`](prepare_first_results.csv).

The optimization trades CPU work for elapsed time. Compared with the
commit-local scheduler, total user plus system CPU time increased by 88.8% on
`jq`, 82.4% on `libuv`, and 69.6% on `libgit2`. Average CPU utilization rose
from 179% to 641% on `jq` and from 253% to 791% on `libuv`. Peak RSS remained
below 600 MiB for all prepare-first runs on the 11 GiB test machine.

## Prepare-first phase breakdown

| Repository | Discovery | Global tokenization | Reconstruction | Total wall |
|---|---:|---:|---:|---:|
| jq | 10.11 s | 53.38 s | 65.30 s | 130.38 s |
| libuv | 28.31 s | 422.25 s | 143.08 s | 611.33 s |
| libgit2 | 57.06 s | 845.13 s | 1,900.77 s | 2,891.41 s |

The bottleneck moves as the repository grows. Global tokenization is the
largest phase on `libuv`, but sequential reconstruction becomes dominant on
`libgit2`. This is consistent with the JFR profile: about 95% of sampled JVM
CPU was in JGit SHA-1 and collision-checking code, and about 61% of sampled
allocation was associated with pack loading, decompression, and blob-array
cloning. The next optimization should therefore avoid redundant source-blob
reads and destination reinsertion during reconstruction rather than adding
more tokenizer workers.

## Correctness and restart behavior

The implementation keeps the original five positional arguments and adds an
opt-in `--prepare-first` flag. Pending task metadata is stored in the new
SQLite `blob_task` table; source and tokenized bytes are not retained there.
Each worker holds only its in-flight blob and uses a thread-confined JGit
inserter. The main thread atomically writes `blob_map` and removes the task.
If the process stops after object insertion but before the SQLite transaction,
the task is safely repeated and Git deduplicates the object.

The `blobExec` test suite now has 43 passing tests. New cases cover queue
deduplication, bounded reads, atomic completion, exact Git-history equivalence,
path-sensitive keys, and resume after an abort. Clean `jq` and `libuv` A/B
runs produced identical refs, `blob_map`, and `commit_map` rows. The prepared
repositories also pass `git fsck --strict` and finish with zero pending tasks.
An additional Perl regression test contributes 19 assertions for deterministic
memo output, extension-aware keys, failure retry, and concurrent access.

The `libgit2` baseline used for timing predates the deterministic temporary
filename fix described below, so it was not used for an exact SHA comparison.
Medium-scale exact equivalence is established by the clean `libuv` pair.

## Reproducibility defect found during A/B validation

The first clean comparison exposed a pre-existing nondeterminism in
`tokenBySha.pl`: Universal Ctags incorporates the input filename into hashes
used for anonymous declaration names, while the wrapper supplied a random
temporary filename. Two clean runs could consequently emit different
`DECL|...|__anon...` tokens and different Git object ids.

The wrapper now uses a deterministic input path derived from a versioned
content-plus-extension key and striped file locks. The extension is part of
the memo key because identical bytes can require different language handling.
A direct reproduction now emits identical SHA-256 output across independent
clean memo directories, and the subsequent full A/B runs are identical.

## Complexity

Let `C` be the number of commits, `B` the globally unique `(blob, path)` tasks,
`P` the worker count, `S` the total bytes passed through tokenizers, and `E`
the tree entries visited during reconstruction.

The commit-local scheduler has linear total work, but its scheduling span is
approximately:

```text
sum over commits c of tokenization_span(tasks_in_c, P)
```

For histories where most commits expose only one or two misses, this is close
to serial execution even when `P` is large.

Prepare-first keeps the same asymptotic tokenization work but changes its span
to approximately:

```text
O(S / P + largest_blob_cost)
```

It adds a discovery traversal and a separate reconstruction traversal, so its
total work remains linear but with a larger constant:

```text
O(C + E + S) discovery/preparation + O(C + E) reconstruction
```

Task bytes in memory are bounded by the active workers; the SQLite queue and
Git object database hold persistent state. In the implementation, each batch
contains at most `16 * P` task records, while only `P` transformations execute
at once.

## Recommendation

Keep `--prepare-first` opt-in until the remaining corpus and repeated-run
variance are measured. The implementation is a valid optimization candidate:
it preserves output on exact A/B runs, remains well within the machine's RAM,
and provides 1.3x to 1.9x wall-clock improvement. It is not a universal final
architecture because it nearly doubles CPU work on smaller corpora and makes
reconstruction the dominant phase on `libgit2`.

The recommended next experiment is a destination-object existence/copy cache
inside reconstruction. It should target the profiled JGit SHA-1 work while
preserving the two-pass scheduler, then repeat the same exact A/B method.
