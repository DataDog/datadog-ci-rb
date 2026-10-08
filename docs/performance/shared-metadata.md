# Tracer performance optimization journal

- Tracer: datadog-ci-rb
- Goal: Remove per-span Git/CI metadata storage and measure test instrumentation overhead
- Created: 2026-10-08T14:34:06+00:00

This journal is append-only. Record every accepted, rejected, and inconclusive iteration.

## Iteration 1: inconclusive

- Timestamp: 2026-10-08T16:01:27+00:00
- Source: /private/tmp/datadog-ci-rb-sdtest-3877
- Branch: anmarchenko/sdtest-3877-deduplicate-metadata
- HEAD: c1d49dbf21d33d0eef1ff735af3570223b92d7f1
- Dirty: no

### Hypothesis

Removing repeated insertion and serialization of shared Git/CI tags reduces per-test instrumentation overhead. This source-based hypothesis follows the requested metadata ownership change; the profile does not establish these operations as a dominant bottleneck.

### Change

Store eligible environment metadata once in Context, expose it through CI getters and the component API, reject generic writes to SDK-owned fields, migrate internal writes, and remove transport override/clear reconciliation.

### Functional tests

- Crook RuboCop and Rails gates: **passed** — Both reference and candidate passed all 36 assertions in each workload.
- Ruby core and integrations: **passed** — Core: 2409 examples, 0 failures, 1 pending before the main merge. RSpec: 150; Minitest: 81; SimpleCov: 25; Knapsack: 23; Selenium and Cuprite: 1 each, all passing.
- Main compatibility and repository checks: **passed** — 107 TIA/suite regressions passed after adapting newly merged suite counters. StandardRB (506 files), architecture and Steep passed. GitHub CI on c1d49dbf21d33d0eef1ff735af3570223b92d7f1: 286 successful checks, 1 skipped, no failures.

### Benchmarks

- ruby-rubocop: **inconclusive**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20261008-163413.344426000-ruby-rubocop-p28767-196b1b9f701ca0cc/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20261008-171800.847998000-ruby-rubocop-p18833-b0b473ac73c828c1/result.json`
  - Comparison: `/private/tmp/651-rubocop-comparison.json`
- ruby-quotes-rails: **inconclusive**
  - Reference: `/private/tmp/651-benchmark-guard/benchmark-data/runs/20261008-174651.496301000-ruby-quotes-rails-p54019-dba21af5c4e46868/result.json`
  - Candidate: `/private/tmp/651-benchmark-guard/benchmark-data/runs/20261008-175230.669025000-ruby-quotes-rails-p54009-27d7c150f638271b/result.json`
  - Comparison: `/private/tmp/651-rails-comparison.json`

### Profiles

- pf2: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20261008-163413.344426000-ruby-rubocop-p28767-196b1b9f701ca0cc/profiles/pf2/profile-2869.pf2.json` — Reference capture: 94.1% of self samples are unresolved; Transport#encode_span has about 0.5% inclusive samples. Attribution is insufficient to confirm the hypothesized bottleneck. Summary: /private/tmp/651-reference-profile-summary.md. No fresh candidate profile was captured.

### Findings

Measured reference 93d16d6a8fd60b4088d791fa0da3b16481095cad from /private/tmp/datadog-ci-rb-651-reference (git archive) against clean candidate 8c691968e3b5b226469b2e002f2c868c1a4cea54 on anmarchenko/sdtest-3877-deduplicate-metadata at /private/tmp/datadog-ci-rb-sdtest-3877. Candidate source remained unchanged during all measurements; the subsequent main compatibility merge c1d49dbf was tested separately and was not benchmarked. Both workloads used the checked-in commands/environment and five measured pairs: RuboCop had zero warmups, Rails had two. The reference primary captured a post-timing Pf2 profile; candidate and guards intentionally omitted profiling. RuboCop reported overhead changed from 24.17% to 20.62%; the deterministic paired-ratio comparison had a 95% change interval of -17.99% to +62.69%. Rails reported overhead changed from 5.58% to 5.38%, with a change interval of -9.28% to +9.99%. Both comparisons are inconclusive at the default 2% practical threshold. All samples were retained. Other local validation/setup work overlapped parts of the RuboCop runs, and the reference included a large baseline outlier. The initial Rails gate in the shared playground failed on a pre-existing intentional-failure reproduction; that file was preserved, and both reported Rails runs instead used a clean detached checkout of c8bcfd7 in /private/tmp/651-benchmark-guard. An initial symlink-based config was rejected before execution and replaced with unchanged tracked config and assertion files. No measured runtime speedup or allocation reduction is established. The requested storage/API behavior is retained independently of performance acceptance; regression tests confirm shared Git/CI entries are absent from individual test-level span metadata.

### Next step

Stop this performance iteration without claiming a speedup. Keep CI/review monitoring active. Any further performance claim needs controlled measurements with no competing local work and a profile with usable attribution.
