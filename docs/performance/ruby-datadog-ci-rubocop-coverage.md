# Tracer performance optimization journal

- Tracer: datadog-ci-rb
- Goal: Reduce full-suite RuboCop TIA coverage overhead from 77.87% to below 50% while keeping the functional gate and Ruby regression guards green
- Created: 2026-08-11T15:39:31+00:00

This journal is append-only. Record every accepted, rejected, and inconclusive iteration.

## Iteration 1: accepted

- Timestamp: 2026-08-11T16:06:21+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-coverage
- HEAD: 34253b65060ce392f683f6ee5705ef7919bf8980
- Dirty: yes

### Hypothesis

RuboCop repeatedly alternates among files within an example, while DDCov only suppresses consecutive events from the same source file; caching every source-file pointer seen by the current test will avoid redundant frame and path processing without changing the coverage set.

### Change

Replace DDCov's last-filename pointer with a per-test native set of observed filename pointers and clear it when coverage stops.

```text
.../ruby-datadog-ci-rubocop-coverage.md            |  7 +++++++
 ext/datadog_ci_native/datadog_cov.c                | 24 ++++++++++++++--------
 2 files changed, 23 insertions(+), 8 deletions(-)
```

### Functional tests

- DDCov native specs: **passed** — Ruby 3.3.5; 37 examples, 0 failures
- ruby-rubocop-coverage Crook gate: **passed** — All 37 assertions passed for the complete upstream RuboCop suite

### Benchmarks

- ruby-rubocop-coverage: **improved**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-165044.786436000-ruby-rubocop-coverage-p46106-6bdb2e7f129973c0/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-174937.180428000-ruby-rubocop-coverage-p85160-737569f8b81f24a9/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-174937.180428000-ruby-rubocop-coverage-p85160-737569f8b81f24a9/comparison.json`

### Profiles

- pf2: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-174937.180428000-ruby-rubocop-coverage-p85160-737569f8b81f24a9/profiles/pf2` — on_line_event fell from 5.22% to 4.44% inclusive and the VM trace path fell from 12.23% to 10.87%; allocation finalization is now the largest direct DDCov hotspot at 5.71%.

### Findings

The green candidate reduced overhead from 77.87% to 72.79%, a 5.08 percentage-point improvement. The deterministic multiplier verdict is improved (-2.86%). Avoiding repeated per-file processing helps, but the VM still invokes the line hook for every executed line, and allocation finalization remains expensive.

### Next step

Cache allocation-tracing class-to-source resolution across tests so repeated classes and ancestor chains do not call const_source_location at every DDCov#stop. Run non-coverage regression guards before final acceptance once the under-50% target is reached.

## Iteration 2: accepted

- Timestamp: 2026-08-11T16:25:03+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-coverage
- HEAD: ea1b5d6f207444298f3093069b5450d5df2a9d5e
- Dirty: yes

### Hypothesis

Allocation tracing repeatedly resolves the same allocated classes and ancestor constant locations at the end of thousands of tests; caching each class's in-project ancestor files for the collector lifetime will eliminate this repeated DDCov#stop work without mixing per-test coverage.

### Change

Add a GC-safe native class-to-files cache while retaining the existing per-test allocated-class table; cached files are copied into only the current test's impacted-files set.

```text
ext/datadog_ci_native/datadog_cov.c | 57 ++++++++++++++++++++++++++-----------
 1 file changed, 41 insertions(+), 16 deletions(-)
```

### Functional tests

- DDCov native specs: **passed** — Ruby 3.3.5; 37 examples, 0 failures
- ruby-rubocop-coverage Crook gate: **passed** — All 37 assertions passed for the complete upstream RuboCop suite

### Benchmarks

- ruby-rubocop-coverage: **improved**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-174937.180428000-ruby-rubocop-coverage-p85160-737569f8b81f24a9/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-180824.256267000-ruby-rubocop-coverage-p3881-8d7ee266ef7818d5/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-180824.256267000-ruby-rubocop-coverage-p3881-8d7ee266ef7818d5/comparison.json`

### Profiles

- pf2: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-180824.256267000-ruby-rubocop-coverage-p3881-8d7ee266ef7818d5/profiles/pf2` — DDCov#stop, each_instantiated_klass, and dd_ci_resolve_const_to_file fell out of the focused top frames; vm_trace is now the dominant coverage path at 10.99%, with on_line_event at 4.66%.

### Findings

The candidate reduced overhead from 72.79% to 66.17%, a 6.62 percentage-point improvement. The deterministic multiplier verdict is improved (-3.83%), and the profile confirms the intended allocation-finalization work was removed rather than shifted.

### Next step

Reduce the per-line VM event-hook cost while preserving coverage for method, block, class-body, and dynamically loaded top-level code. Run non-coverage regression guards before final acceptance once overhead is below 50%.

## Iteration 3: rejected

- Timestamp: 2026-08-11T16:35:53+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-coverage
- HEAD: a3ca9ef9d97bf69d7831e01f66758631e74b7718
- Dirty: yes

### Hypothesis

Replacing multi-thread line events with Ruby method, block, class, and script-compilation events will preserve file coverage while avoiding the dominant per-line VM trace-hook cost.

### Change

Use a normal TracePoint for CALL, B_CALL, CLASS, and SCRIPT_COMPILED in multi-thread mode; retain line hooks in single-thread mode and add a top-level-only dynamic-load fixture.

```text
ext/datadog_ci_native/datadog_cov.c | 49 +++++++++++++++++++++++++++++++++++--
 spec/ddcov/ddcov_spec.rb            | 12 +++++++++
 2 files changed, 59 insertions(+), 2 deletions(-)
```

### Functional tests

- DDCov native specs: **passed** — Ruby 3.3.5; 38 examples, 0 failures, including dynamic top-level code
- ruby-rubocop-coverage Crook gate: **failed** — Interrupted after 7 minutes because the functional workload exceeded twice the accepted implementation's duration; Crook cleanup succeeded

### Benchmarks

- ruby-rubocop-coverage: **regressed**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-180824.256267000-ruby-rubocop-coverage-p3881-8d7ee266ef7818d5/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-182812.724018000-ruby-rubocop-coverage-p21019-c8b4f14a475ea8a9/status.json`

### Findings

RuboCop executes Ruby method and block entry events far more often than it alternates among distinct source files after the per-test filename cache. The lower-frequency assumption was false for this workload, so the functional phase alone was enough to reject the candidate without contaminating the accepted reference.

### Next step

Keep line events and optimize the hot early-return path itself, especially avoiding TypedData extraction and general st_table lookup on every event.
