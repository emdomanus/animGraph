# Evaluation benchmark

Run from the package root with PowerShell 7. The wrapper resolves the pinned Lune
through Rokit and runs the benchmark through the existing guarded test runner, so
transformed modules have the same owned-runtime cleanup as the regression suites.

```powershell
pwsh -NoProfile -File scripts/bench/run.ps1 -OutDir .verification/my-benchmark
```

Use a fresh output directory for each run. Optional `-Iterations` and `-Rounds`
default to 20,000 and seven. Each round constructs a new controller, warms it with
2,000 updates, then times only its update loop. Setup, module transformation,
logging, serialization, and teardown are excluded. Ordinary garbage collection
remains enabled; the benchmark does not estimate allocated bytes.

Cases exercise the real controller, layers, clips, and blends. Sink cases consume
requests without retaining batches. The native case exercises eight layers and
the real native Roblox backend against the existing fake Animator. All cases use
one borrowed time-sample table. Blend parameters vary deterministically; no debug
snapshot is requested during timing. These are host Lune measurements, not Studio
engine timings or a measurement of sampled-position playback.

`results.json` contains every measured interval and a sink checksum. `metadata.json`
records the source hashes, benchmark hash, commit, and resolved tool identity.
Compare identical benchmark versions and inputs; checksums supplement, rather than
replace, the behavioral regression tests.

## Recorded comparison

Baseline source: `617d800` (positional generics). The uncommitted performance
checkpoint reuses private blend and validation scratch, leases backend touched-key
maps, allocates omission lists only when needed, skips empty completion dispatch,
reuses controller callbacks, and processes a bounded command prefix without copying.
It preserves allocating motion results and backend batches, both validation
boundaries, and the existing Blend2D full sort and tie behavior. Public evaluation,
snapshot, and backend interfaces are unchanged.

The confirmation used A/B/B/A process order: two seven-round captures per variant,
14 intervals per case, 20,000 measured updates per interval. Both A source captures
and both B source captures had matching hashes. All four captures used the same
benchmark and pinned Lune 0.8.9. All sink checksums matched exactly. Original source
was temporarily restored for A captures, then the performance edits were restored
byte-for-byte. Evidence is under ignored `.verification/perf-confirmation/`.

| Case | Before median µs/update | After median µs/update | Time reduction |
| --- | ---: | ---: | ---: |
| One clip, sink | 2.890 | 2.633 | 8.9% |
| Blend1D, 16 samples, sink | 5.329 | 4.987 | 6.4% |
| Blend2D, 16 samples, sink | 11.061 | 10.083 | 8.8% |
| Blend2D, 64 samples, sink | 22.555 | 20.294 | 10.0% |
| Native backend, eight layers | 27.147 | 25.457 | 6.2% |

Ranges overlap in the smaller cases; these results are not a confidence interval
or a promise of the same engine speedup. The 64-sample and eight-layer native cases
had non-overlapping measured ranges. No packed buffers or borrowed public
request-batch API were introduced.

## Ownership of reused storage

Each reusable scratch table is detached from its owner while in use. A nested
evaluation or validation obtains separate storage. Blend failures abandon the
leased scratch safely; the next successful evaluation replenishes it. Validation
maps and backend touched-key maps are cleared before reuse so they retain capacity
without retaining prior request keys. Nested successful calls may leave the one
cached spare; outer calls do not overwrite it. Scratch capacity follows the
largest successful workload, rather than allocating fresh storage every frame.

`tests/lune/evaluationReuse.spec.luau` runs through the default test suite and covers
nested blend evaluation, exact-hit/reset sequences, recovery after a child throws,
retained requests and debug snapshots, failed/nested validation, nested backend
apply, and retained controller batches. The original 87 behavioral cases remain
unchanged.
