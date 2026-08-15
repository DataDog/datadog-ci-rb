# Rails TIA stress optimization outcome

- Tracer: datadog-ci-rb
- Workload: `ruby-rails-tia-stress-test-level`
- Correctness priority: deterministic, substantially complete TIA coverage is the primary constraint
- Final target: 32% overhead
- Outcome: target not reached; final safe candidate measures 51.50% overhead
- Completed: 2026-08-15

This document records the final disposition of the optimization loop. Bounded,
explicit blind spots were acceptable during exploration. Broad coverage loss,
sampling, timing-dependent behavior, or load-order-dependent behavior were not.

## Benchmark contract

The benchmark runs 1,000 Rails examples. Its correctness gate requires all
19,080 assertions, 1,000 coverage events, and the exact expected file
associations before any timing is accepted. The baseline is the uninstrumented
workload; the instrumented variant enables normal test tracing and TIA
test-level coverage. The separate `ruby-rails-tia-stress-default` benchmark is
the tracing-only floor.

The repository root is invariant for the lifetime of the process and never
changes between coverage events. Coverage serialization may therefore capture
and reuse that root instead of repeatedly resolving it.

DDCov supports exactly one active instance and one collector per process.
Instances may be reused or activated sequentially, including from different
threads. An overlapping start fails deterministically.

## Retained changes

The final candidate keeps only optimizations that preserve the existing
coverage event sources and pass the cross-workload guards:

- Register the NEWOBJ callback as a raw VM event hook, avoiding the TracePoint
  wrapper. The callback introduces no general Ruby API calls; `rb_mod_name` is
  the explicitly permitted safe lookup.
- Normalize, deduplicate, and MessagePack coverage filenames in one native
  operation. The common all-absolute shape writes suffix bytes relative to the
  immutable repository root without allocating relative Strings. Unsupported
  shapes fall back before the packer is mutated.
- Use `Zlib::BEST_SPEED` for CI test-coverage payloads only. Other request types
  retain their existing compression behavior.
- Enforce and document the one-active-DDCov-collector contract.

Native and Ruby serialization were verified byte-for-byte for native paths,
relative and absolute custom paths, duplicates, UTF-8, binary filenames,
long filenames, and arrays requiring non-fixarray MessagePack headers.

## Rejected event architecture

A target-bound CALL/B_CALL/LINE architecture replaced the global multi-thread
line hook and produced the best Rails point estimate. It reached 33.64%
overhead while preserving the Rails stress gate, and a later combined candidate
reached an inconclusive 29.79% point estimate.

The same architecture was disastrous on the required full
`ruby-rubocop-coverage` guard. Its functional workload exceeded ten minutes at
approximately 99% CPU, compared with roughly three minutes on current main.
Checkpoint isolation identified the target-event commit as the regression
boundary. The architecture was therefore rejected in full despite its Rails
result. No target collector, target TracePoint, or CALL/B_CALL replacement is
present in the final candidate.

This is the reason the 32% Rails target is considered unreachable within the
accepted correctness and cross-workload constraints.

## Final validation

### Rails TIA stress

- Status: passed
- Correctness: all 19,080 assertions passed
- Protocol: 1 warmup pair, 4 measured pairs
- Baseline median: 34,700.27 ms
- Instrumented median: 52,570.26 ms
- Final overhead: **51.50%**
- Artifact:
  `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260815-024102.326825000-ruby-rails-tia-stress-test-level-p57606-1a7d52c1274ee45d/result.json`

All timed children exited successfully. There was no macOS-sleep gap. The
fourth pair was slower in both variants and had proportionally high user CPU;
the reported median is determined by the stable middle samples.

### RuboCop coverage guard

- Current main: 52.17% overhead
- Final candidate: 53.45% overhead
- Correctness: all 37 assertions passed for both
- Runtime multiplier change: +0.02%
- 95% interval: -2.65% to +3.40%
- Verdict: inconclusive; no practical regression detected

Reference:
`/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260814-231143.560352000-ruby-rubocop-coverage-p65216-ad32ead4baa68798/result.json`

Candidate:
`/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260815-003007.666284000-ruby-rubocop-coverage-p21376-181ce166cb319fca/result.json`

### Quotes Rails guard

- Current main: 7.65% overhead
- Final candidate: 8.35% overhead
- Correctness: all 36 assertions passed for both
- Runtime multiplier change: -0.50%
- 95% interval: -13.62% to +11.32%
- Verdict: inconclusive; no practical regression detected

Reference:
`/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260815-010349.126843000-ruby-quotes-rails-p39475-cbe2424c086ea8ae/result.json`

Candidate:
`/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260815-023112.785462000-ruby-quotes-rails-p49574-17567978fd9d0b18/result.json`

The long gap in the current-main Quotes run occurred between timed child
processes because macOS slept. It is not included in any recorded duration.

## Decision

Stop the loop and ship the safe subset. It reduces deterministic tracer work
without changing the coverage event model, keeps the exact Rails correctness
gate green, and has no detected practical regression on RuboCop coverage or
Quotes Rails. The 32% target is explicitly not claimed.
