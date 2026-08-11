# Ruby datadog-ci RuboCop optimization journal

- Tracer: datadog-ci-rb
- Goal: Reduce full-suite RuboCop tracer overhead from approximately 42% to 25% or lower while keeping RuboCop and Quotes Rails functional gates green
- Created: 2026-08-11T09:33:42+00:00

This journal is append-only. Record every accepted, rejected, and inconclusive iteration.

## Imported reference analysis (2026-08-10)

This context was imported from Shepherd's local
`benchmark-data/optimization/ruby-datadog-ci-rubocop.md`. The analysis produced
a hypothesis, but no tracer change was implemented or measured.

- `datadog-ci-rb`: `c33f9055f8b69dc0c6fcbbfb76fc1d55fbcc7375`
- `dd-trace-rb`: `1541704c183d44a942d28af7302030aa3e30da71`
- Functional gate: passed for 21,742 tests and 663 suites
- Protocol: 1 warmup pair and 4 measured pairs
- Baseline median: 117,048.81 ms
- Instrumented median: 165,785.25 ms
- Tracer overhead: 41.64%
- Result: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260810-175016.522013000-ruby-rubocop-p82789-0bfb3dd9ea2f2a0b/result.json`
- Pf2 profile: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260810-175016.522013000-ruby-rubocop-p82789-0bfb3dd9ea2f2a0b/profiles/pf2/profile-95127.pf2.json`
- Profile size: 9,170 CPU samples at a 10 ms interval

The Datadog-owned sampled hot paths were:

| Hot path | Samples | Approximate sampled CPU | Profile share |
| --- | ---: | ---: | ---: |
| `Span#set_environment_runtime_tags` -> `Platform.kernel_release` -> `Etc.uname` | 242 | 2.42 s | 2.64% |
| `LocalRepository.relative_to_root` -> `File.expand_path` / `Pathname#relative_path_from` | 193 | 1.93 s | 2.10% |

The first hypothesis is that environment/runtime values are process constants
but `TestTracing::Context#set_initial_tags` recomputes them for every test span.
Caching those values should remove most of the `kernel_release` samples without
changing emitted span tags. Test this independently before considering the next
hypothesis: normalize leading `./` paths or cache repeated
`LocalRepository.relative_to_root` results.

## Iteration 1: accepted

- Timestamp: 2026-08-11T11:01:00+00:00
- Source: /private/tmp/datadog-ci-rubocop-optimization
- Branch: anmarchenko/optimize-rubocop-overhead
- HEAD: f4bc8d8832c614c065193dc7c5a1035ababd73ae
- Dirty: yes

### Hypothesis

Every test span recomputes process-static environment/runtime tags, and repeated Platform.kernel_release calls account for the stable 2.66% Pf2 hotspot.

### Change

Cache the five process-static environment/runtime tags once in Span::ENVIRONMENT_RUNTIME_TAGS and apply them as a single tag hash while preserving first-span command capture.

```text
docs/performance/ruby-datadog-ci-rubocop.md | 38 +++++++++++++++++++++++++++++
 lib/datadog/ci/span.rb                      | 14 +++++++----
 sig/datadog/ci/span.rbs                     |  2 ++
 spec/datadog/ci/span_spec.rb                | 12 +++++----
 4 files changed, 56 insertions(+), 10 deletions(-)
```

### Functional tests

- Focused Span spec: **passed** — 48 examples, 0 failures
- StandardRB: **passed** — 2 changed Ruby files, no offenses
- Steep: **passed** — No type errors
- ruby-rubocop Crook gate: **passed** — All 36 assertions
- ruby-quotes-rails Crook gate: **passed** — All 36 assertions

### Benchmarks

- ruby-rubocop: **inconclusive**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-113435.383645000-ruby-rubocop-p95795-dfeafcd50c90d583/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-122237.137730000-ruby-rubocop-p26019-b2d268cf1b6675fc/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-122237.137730000-ruby-rubocop-p26019-b2d268cf1b6675fc/comparison.json`
- ruby-quotes-rails: **inconclusive**
  - Reference: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-120101.510128000-ruby-quotes-rails-p13661-342e39e2889871c8/result.json`
  - Candidate: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-125324.489488000-ruby-quotes-rails-p39204-dd1bb11862646f69/result.json`
  - Comparison: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-125324.489488000-ruby-quotes-rails-p39204-dd1bb11862646f69/comparison.json`

### Profiles

- pf2: `/Users/andrey.marchenko/p/shepherd/benchmark-data/runs/20260811-122237.137730000-ruby-rubocop-p26019-b2d268cf1b6675fc/profiles/pf2` — set_environment_runtime_tags fell from 244 samples (2.66%) to 3 samples (0.03%); relative_to_root is now the leading visible Datadog hotspot at 223 samples (2.30%).

### Findings

RuboCop overhead fell from 44.12% to 40.57%, a 3.55 percentage-point reduction accepted by the user despite the conservative comparison verdict. Quotes Rails moved from 7.28% to 6.17% and did not show a regression. The profile independently confirms that the targeted kernel-release work disappeared.

### Next step

Before another code change, reconcile the approximately 49 seconds of RuboCop wall-time overhead with the roughly 4 seconds represented by the two visible Datadog Pf2 hotspots; inspect CPU time, all profile processes and threads, GC/allocation cost, and blocking/GVL behavior to identify the missing approximately 45 seconds.
