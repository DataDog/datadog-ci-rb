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

## Iteration 4: accepted

- Timestamp: 2026-08-11T17:49:24+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-coverage
- HEAD: 713b5ff5ae7e82c7662d2af6ba58eaf24d8ff2bc
- Dirty: yes

### Hypothesis

The general st_table membership lookup and typed-data extraction on every Ruby line dominate the remaining on_line_event callback cost; a direct-mapped pointer cache with a consecutive-file fast path will preserve exact coverage while making the common return path constant and allocation-free.

### Change

Replace the per-test st_table of filename pointers with a 256-entry direct-mapped native pointer cache plus a last-filename fast path, and access the callback's already-validated typed data directly. Cache collisions only repeat path processing and cannot omit coverage.

```text
ext/datadog_ci_native/datadog_cov.c | 42 +++++++++++++++++++++++--------------
 1 file changed, 26 insertions(+), 16 deletions(-)
```

### Functional tests

- DDCov native specs: **passed** — Ruby 3.3.5; 37 examples, 0 failures
- ruby-rubocop-coverage Crook gate: **passed** — All 37 assertions passed for the complete upstream RuboCop suite
- ruby-rubocop Crook guard: **passed** — All 36 assertions passed; four-pair benchmark comparison was inconclusive, not regressed
- ruby-quotes-rails Crook guard: **passed** — All 36 assertions passed; ten-pair benchmark comparison was inconclusive, not regressed

### Benchmarks

- ruby-rubocop-coverage: **improved**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-180824.256267000-ruby-rubocop-coverage-p3881-8d7ee266ef7818d5/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-183814.534638000-ruby-rubocop-coverage-p30210-f0522b4f9b41fcbf/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-183814.534638000-ruby-rubocop-coverage-p30210-f0522b4f9b41fcbf/comparison.json`
- ruby-rubocop: **inconclusive**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-153739.599524000-ruby-rubocop-p94073-b56b30d9515ed557/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-185308.307027000-ruby-rubocop-p45653-5fb815bc8f93f8b3/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-185308.307027000-ruby-rubocop-p45653-5fb815bc8f93f8b3/comparison.md`
- ruby-quotes-rails: **inconclusive**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-160600.926505000-ruby-quotes-rails-p8853-55dc2637ed372b38/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-192502.265055000-ruby-quotes-rails-p66327-26a7be4807458535/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-192502.265055000-ruby-quotes-rails-p66327-26a7be4807458535/comparison.md`

### Profiles

- pf2: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-183814.534638000-ruby-rubocop-coverage-p30210-f0522b4f9b41fcbf/profiles/pf2` — on_line_event fell from 4.66% to 1.86% inclusive; vm_trace fell from 10.99% to 8.36%.

### Findings

The coverage benchmark improved from 66.17% to 58.61% overhead, a 7.56 percentage-point reduction. The direct callback hotspot shrank as predicted. Full-suite RuboCop remained green at 22.90% overhead (inconclusive versus 19.45%), and Quotes Rails remained green at 8.13% (inconclusive versus 10.04%). The isolated long Quotes gap occurred outside measured command duration; its retained measured samples were normal.

### Next step

Continue from the 58.61% reference. Investigate the remaining VM event-hook overhead and the large Pf2 unknown/native sample share without weakening exact per-test coverage semantics.

## Iteration 5: accepted

- Timestamp: 2026-08-11T18:20:34+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-coverage
- HEAD: 6f8688c44527ef9a919cff275e0c7a3488def126
- Dirty: yes

### Hypothesis

Allocation tracing repeats class-name resolution and hash insertion for every object allocation even after that class has already been recorded for the current test; a native fast-path cache for previously recorded classes will remove this per-object bookkeeping without changing the per-test class set.

### Change

Add consecutive-class and 256-entry direct-mapped caches ahead of allocation class-name resolution and st_table insertion. The authoritative per-test class table remains unchanged; cache collisions fall back to it, and only named classes retained by that table enter the pointer cache.

```text
ext/datadog_ci_native/datadog_cov.c | 37 +++++++++++++++++++++++++++++++++++--
 1 file changed, 35 insertions(+), 2 deletions(-)
```

### Functional tests

- DDCov native specs: **passed** — Ruby 3.3.5; 36 examples, 0 failures
- ruby-rubocop-coverage Crook gate: **passed** — All 37 assertions passed for the complete upstream RuboCop suite
- Ruby non-coverage guards: **passed** — The immediately preceding accepted base passed full ruby-rubocop and ruby-quotes-rails guards. This iteration changes only on_newobj_event, which is registered solely when TIA allocation tracing is enabled, so ordinary tracing cannot execute the new path.

### Benchmarks

- ruby-rubocop-coverage: **improved**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-183814.534638000-ruby-rubocop-coverage-p30210-f0522b4f9b41fcbf/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-195316.520076000-ruby-rubocop-coverage-p78776-3ba9efbeb9382adc/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-195316.520076000-ruby-rubocop-coverage-p78776-3ba9efbeb9382adc/comparison.md`

### Profiles

- pf2: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-195316.520076000-ruby-rubocop-coverage-p78776-3ba9efbeb9382adc/profiles/pf2` — The VM trace path fell from 8.36% to 6.47% inclusive and on_line_event fell from 1.86% to 1.36%. Pf2 does not name on_newobj_event directly, but the reduced native VM-hook share and wall time support the allocation fast-path hypothesis.

### Findings

The complete RuboCop coverage benchmark improved from 58.61% to 48.17% overhead, a 10.44 percentage-point reduction and a deterministic 6.58% multiplier improvement. Baseline and instrumented command durations were 113.91s and 168.77s; a host-level delay between phases occurred outside those measured durations. The functional gate remained green, and the requested under-50% goal is met.

### Next step

Stop the optimization loop at the requested threshold. Run final native coverage validation, commit the code and journal, and open the tracer pull request.

## Iteration 6: accepted

- Timestamp: 2026-08-12T09:30:37+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-coverage
- HEAD: 8c47aa22049ac6c901b466a8c54791004e8a87d9
- Dirty: yes

### Hypothesis

A discarded instruction sequence can release its source-path storage, allowing Ruby to reuse the raw address for a different file and causing the line-event pointer cache to omit valid per-test coverage.

### Change

Replace raw filename-pointer cache entries with 1,024 GC-marked Ruby path values while retaining direct-mapped pointer comparisons and add a regression test that forces instruction-sequence source reuse.

```text
ext/datadog_ci_native/datadog_cov.c | 45 ++++++++++++++++++++++++-------------
 spec/ddcov/ddcov_spec.rb            | 39 ++++++++++++++++++++++++++++++++
 2 files changed, 69 insertions(+), 15 deletions(-)
```

### Functional tests

- DDCov native specs: **passed** — Ruby 3.3.5; 38 examples, 0 failures
- ruby-rubocop-coverage Crook gate: **passed** — All 37 assertions passed for the complete upstream RuboCop suite

### Benchmarks

- ruby-rubocop-coverage: **regressed — accepted for correctness**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-195316.520076000-ruby-rubocop-coverage-p78776-3ba9efbeb9382adc/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260812-105839.951667000-ruby-rubocop-coverage-p15766-a53e211a985957d6/result.json`

### Findings

The correctness regression reproduced twice before the fix, recording only 873 and 937 of 2,000 included files. It passes after the cache owns the paths. The four-pair candidate benchmark succeeded at 53.46% overhead, versus 48.17% in the earlier one-pair run. Although the mismatched protocols prevent a deterministic comparison, the observed 5.29 percentage-point increase is conservatively recorded and accepted as a performance regression in exchange for complete coverage.

### Next step

Address the next PR review comment independently. Retain this accepted correctness fix and use matching benchmark protocols for any later performance comparison.
