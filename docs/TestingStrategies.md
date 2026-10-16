# Testing strategies

This document covers the existing testing stack and the new mutation/property
testing POC, checked against repository configuration on 2026-09-18. It describes
configured workflows, not the status of their latest remote runs. The POC adds
property and mutation CI jobs; production code is unchanged.

The goals are to preserve customer test results, avoid unsafe skipping, keep
instrumentation failures out of customer test processes, prevent native memory
errors, and keep instrumentation overhead bounded. Each strategy checks a
different aspect; none establishes that the library is bug-free.

## Strategy overview

| Strategy | What it detects or measures | Current execution |
| --- | --- | --- |
| Example-based unit and component tests | Incorrect outputs, state transitions, error handling and regressions | Existing RSpec CI suites |
| Ruby/framework compatibility matrix | Changes that fail only on particular Ruby or dependency versions | Existing Appraisal-based CI matrix |
| Application integration smoke tests | Installation, boot and framework-instrumentation problems in a sample app | Existing separate Docker CI workflow |
| Concurrency, lifecycle and GC stress | Stale state, thread/fork interactions, invalid object ownership and cache reuse | Existing targeted examples in normal suites; selected files also run under Memcheck |
| Valgrind Memcheck | Native invalid memory accesses, uninitialized-value use, invalid frees and leaks | Existing Linux CI workflow using ruby_memcheck |
| Static checks and security analysis | Type errors, architecture violations, style issues and security findings | Existing StandardRB, RBS/Steep, ArchSpec and Ruby CodeQL workflows |
| Line and branch coverage | Which code and branches tests execute | Existing SimpleCov reports and CI uploads; a measurement rather than a correctness oracle |
| Packaging/install checks | Missing package files, invalid gem metadata and installation/build failures | Existing release specs and gem build/install CI |
| Performance testing | Instrumentation CPU/time overhead and changes in scaling behavior | Existing manual benchmarks and performance journals |
| Property-based testing | Violations across generated inputs and operation sequences | PropCheck POC included in the Git spec glob and a dedicated CI job |
| Mutation testing | Tests that fail to detect deliberately changed code | Dedicated Mutineer CI job enforcing a 100% score; currently expected to fail |
| Coverage-guided fuzzing | Failures reached by inputs evolved using execution feedback | Ruzzy planned for the next phase; currently removed |
| Native compiler sanitizers | Memory/undefined-behavior faults in instrumented native builds | Proposed complementary ASan/UBSan lane; not configured by this POC |

## Normal CI: functional and compatibility testing

The main [Unit Tests workflow](../.github/workflows/test.yml) runs the
[reusable test workflow](../.github/workflows/_unit_test.yml) on MRI Ruby 2.7,
3.0, 3.1, 3.2, 3.3, 3.4 and 4.0. It runs for PRs targeting main, configured push
branches, and every four hours on weekdays. Each Ruby gets the compatible test
groups declared in [`TEST_METADATA`](../Rakefile), using Appraisal gemfiles.

The matrix builds the native extension, runs `spec:<task>`, and uploads JUnit
and coverage artifacts. It covers the core library, Git behavior, native
coverage, and integrations such as RSpec, Minitest, Cucumber and Rails. A passing
test on one Ruby/framework combination does not replace this matrix.

Use focused tests while developing, then the relevant `test:<group>` tasks:

```sh
bundle install
bundle exec appraisal install
bundle exec rake test:main
bundle exec rake test:git
bundle exec rake test:rspec
# All compatible groups for the currently selected Ruby:
bundle exec rake ci
```

`test:*` tasks arrange native compilation and select compatible appraisals.
Direct `spec:*` or `rspec` commands use the currently selected bundle; compile
first when exercising native code. **`rake ci` runs the current Ruby's test
groups**, not every Ruby version or the separate memory, static-analysis,
packaging and app-smoke workflows.

New integration directories need matching Rake tasks and `TEST_METADATA`
entries. Preserve the failing seed and add a deterministic regression when a
bug is found. See the [Development Guide](DevelopmentGuide.md) for Appraisal
selection and focused RSpec commands.

The [daily dependency-update workflow](../.github/workflows/update-latest-dependencies.yml)
refreshes appraisals and opens a dependency-update PR. Updating dependencies
is not itself a correctness test; the resulting PR needs the compatibility
matrix to establish whether the new versions work.

### Application integration and behavioral contracts

The [app integration workflow](../.github/workflows/integration-test.yml) runs on
pushes using Ruby 3.0–3.3 containers. It executes the sample app's RSpec and
Cucumber tasks with instrumentation enabled:

```sh
cd integration/app
BASE_IMAGE=ruby:3.3 docker compose run --rm --no-deps app \
  "bundle install && bundle exec rake test"
```

This is an application smoke check. The workflow uses `--no-deps`, so it does
not start the Compose Datadog Agent service or establish successful backend
delivery. Its Ruby matrix is narrower than the main unit matrix.

For stronger behavioral contracts, integration tests should assert actual test
execution, original test outcomes and framework exit status. Fault injection
at network/cache boundaries can verify graceful degradation. A nonzero exit
alone cannot distinguish an expected test failure from an instrumentation crash.
These are directions for expanded coverage, not claims about the existing smoke
app's assertions.

## Concurrency, lifecycle and garbage-collection stress

Existing [native coverage specs](../spec/ddcov/ddcov_spec.rb),
[source-code specs](../spec/datadog/ci/source_code), and
[writer specs](../spec/datadog/ci/async_writer_spec.rb) exercise threads, fork
handling, forced collection, compaction where supported, and repeated cache use.
These tests belong in ordinary CI because valid memory accesses can still
produce wrong coverage or leak state between test runs.

Run the relevant examples on normal Ruby and under Memcheck when their files
are in its target set. The line-event-cache stress example intentionally uses
2,000 iterations normally and 20 under Memcheck, where forced full-heap GC is
expensive. Thus, a Memcheck run also does not replace the normal stress run.
Controlled synchronization and reproducible sequences make race regressions
more actionable than relying solely on long, timing-dependent loops.

## Valgrind Memcheck: native memory safety

[Memcheck](https://valgrind.org/docs/manual/mc-manual.html) observes memory use
while executing a program. It detects invalid reads/writes, use-after-free,
uninitialized-value use, invalid/double frees and memory leaks. It checks the
executed paths; it does not establish functional correctness or explore all
thread schedules.

The existing [memory workflow](../.github/workflows/test-memory-leaks.yml) runs
on pushes using Ubuntu 24.04 and Ruby 3.4.5. It installs Valgrind and executes:

```sh
# In a Linux environment with Valgrind and Ruby 3.4.5 installed:
bundle install
valgrind --version
bundle exec rake compile spec:ddcov_memcheck
```

[`ruby_memcheck`](https://github.com/Shopify/ruby_memcheck) integrates the Ruby
test runner with Valgrind and filters Ruby-runtime noise. The repository's Rake
task targets `spec/ddcov/**/*_spec.rb` and
`spec/datadog/ci/source_code/**/*_spec.rb`, not the entire test suite. The Gemfile
includes ruby_memcheck on non-JRuby runtimes at Ruby 3.4 or newer.

The [Rake configuration](../Rakefile) enables `use_only_ruby_free_at_exit` and
suppression generation. Repository suppressions live in
[`suppressions/ruby-3.4.supp`](../suppressions/ruby-3.4.supp). Generated suppression
text is diagnostic material, not a reason to automatically hide a report;
establish whether the allocation/access belongs to this library or a known
external issue before changing suppressions.

**Existing skip condition:** when `Libdatadog::VERSION` starts with `30.`, the
task prints a warning and skips Memcheck because of the referenced upstream
Valgrind crash. A successful task exit in that case means no memory analysis
ran. The task raises if ruby_memcheck is unavailable. Inspect execution and
skip output as well as job status when assessing memory-check evidence.

Native crashes, unsuppressed memory reports and test failures require diagnosis.
Retain the stack, failing example, Ruby/libdatadog/Valgrind versions and any
minimized input. Run affected tests normally after a fix as well as under
Memcheck. This documentation update did not execute a new Memcheck campaign.

### Compiler sanitizers: a complementary future lane

ASan/UBSan would require separately instrumented native builds and compatible
runtime/dependency setup. They are intended to detect native memory faults and
undefined behavior on the paths exercised by tests or fuzzing. No such CI lane
is configured by this POC. Their future results should be reported separately
from Valgrind and ordinary Ruby test results.

## Static checks and security analysis

The [Check workflow](../.github/workflows/check.yml) runs on main pushes and PRs
targeting main, using Ruby 3.4:

```sh
bundle exec standardrb
bundle exec rake archspec
bundle exec rake rbs:stale rbs:missing
bundle exec rake steep:check
```

StandardRB checks style and supported static offenses; RBS/Steep checks signatures
and type consistency; ArchSpec checks component boundaries and interface rules.
These checks catch problems without requiring a test to reach the affected
path, but do not establish that runtime decisions are correct. ArchSpec reports
analysis gaps separately; a pass does not mean every dynamic call was resolved.

The separate [CodeQL workflow](../.github/workflows/codeql-analysis.yml) scans
Ruby on main/release pushes and PRs targeting main. Its language matrix contains
Ruby only, so it is not evidence of a CodeQL scan of the native C extension.

## Code coverage: measuring what the tests exercised

[SimpleCov configuration](../.simplecov) enables branch coverage. Unit CI keeps
reports per Ruby/gemfile/task and uploads them alongside JUnit reports; another
job uploads collected results to Datadog. To inspect locally collected results:

```sh
bundle exec rake coverage:report
```

The report is written to `coverage/report/index.html`. Partial local runs only
provide partial coverage. Coverage helps identify unexecuted code and missing
branches; it does not tell whether assertions would detect a wrong result.
Mutation testing supplies evidence about that separate question. No numeric
coverage gate is configured in the inspected SimpleCov file.

## Packaging and installation checks

The [release specs](../spec/datadog/ci/release_gem_spec.rb) validate the gem's file
inventory and its Ruby-version relationship to the tracing dependency. The
[build workflow](../.github/workflows/build-gem.yml) builds final/dev variants,
uploads artifacts and installs those artifacts on Ruby 3.4. Installation catches
packaging/build failures, but does not run the entire suite against the installed
artifact. Publishing is a separate action from these checks.

```sh
# Build locally without publishing:
bundle exec rake build
```

The inventory spec uses `git ls-files`, so new files must be staged with user
approval before validating the full suite. Test helpers and the seed corpus live
under `spec/support/fuzz/`, and the mutation runner lives in `bin/`. These
development directories are excluded from the package inventory check and are
not shipped in the gem.

## Performance and overhead testing

This library must preserve correctness while adding little cost to customer CI.
Existing manual [benchmarks](../benchmarks) measure test-name normalization,
anonymous example names, and the test-impact-analysis lifecycle/serialization:

```sh
bundle exec ruby benchmarks/test_name_normalization.rb
bundle exec ruby benchmarks/rspec_anonymous_example_name.rb
bundle exec ruby benchmarks/test_impact_analysis_impacted_files.rb
```

Use the same Ruby, dependency versions and workload for before/after comparisons,
include warmups and repeated measurements, and keep functional checks alongside
timing results. The [performance journals](performance/ruby-datadog-ci-rubocop.md)
record application-level measurements and experiments. These benchmarks are not
wired into the inspected unit-test workflow as a required performance gate.
Memcheck timings should not be used to estimate normal instrumentation overhead.

## New testing tools: mutation and property testing

**Use Mutineer for mutation testing and PropCheck for property-based testing.**
Both pinned gems declare MIT licenses and have no runtime gem dependencies.

| Tool | License | Role |
| --- | --- | --- |
| [Mutineer](https://davidteren.github.io/mutineer/) 1.0.0 | [MIT](https://github.com/davidteren/mutineer/blob/main/LICENSE) | Selected mutation runner. Prism-based, Ruby 3.4+, RSpec support, coverage-based test selection and JSON reports. Verified against this repository. |
| [PropCheck](https://github.com/Qqwy/ruby-prop_check) 1.0.2 | MIT, verified in the published gem metadata | Seeded input generation and shrinking in normal RSpec tests. Compatible with the library's Ruby 2.7 syntax requirement. |

MIT permits commercial use without purchasing a license; retain the copyright
and license notices when distributing copies or substantial portions. Mutineer's
installed 1.0.0 LICENSE was checked directly. Neither tool adds a runtime
requirement to the distributed datadog-ci gem.

Mutant is excluded because its commercial licensing does not meet the project's
requirements. Ruzzy is reserved for the next fuzzing phase; its AGPL license is
acceptable for that planned work. Both tools' runner integrations have been
removed from the current POC. The retained fuzzing uses generated inputs and
corpus replay; **a coverage-guided fuzzing engine is not currently configured**.

Mutineer has a smaller track record than longer-established mutation tools.
Inspect survivors and timeouts from the targeted CI run. Keep the existing
Ruby/runtime and integration matrix: these techniques
supplement it. A perfect mutation score does not prove the absence of bugs.

## What the POC tests

The POC targets `Datadog::CI::Git::ChangedLines`, whose inclusive interval queries
feed change impact analysis. Property-based tests express invariants across
generated inputs instead of enumerating every input manually. Here, comparison
with an independent reference model checks correctness, while translating all
coordinates checks that behavior is preserved under that transformation.

The shared target treats bytes as a sequence of additions, explicit builds,
and overlap queries. It compares the optimized implementation with an independent
`Set` of individual line numbers. It checks empty state, query results, exact
merged contents and canonical ordering. State is fresh for each input.

The property suite generates 300 operation sequences and 200 interval/query
cases per run. It also translates coordinates by zero and positive/negative
`2**64`, checks endpoints and neighboring points, and replays the checked-in
corpus. PropCheck shrinks a failing generated input. Reproduce it with the same
RSpec seed, tool version and Ruby runtime; retain the minimized example as a
regression test.

The byte target is bounded to 384 bytes (128 operations), with coordinates from
-128 to 127. The property generator currently supplies up to 96 bytes per input;
the separate translation property covers large integers. This POC does not
exercise concurrent callers, the complete skip decision, malformed backend
responses, or the native coverage extension.

## Run property-based testing

From the repository root:

```sh
bundle install
bundle exec rspec spec/datadog/ci/git/changed_lines_spec.rb \
  spec/datadog/ci/git/changed_lines_property_spec.rb \
  spec/datadog/ci/git/diff_spec.rb --seed 20260918
```

The new specs are already included by `bundle exec rake test:git`; no additional
Rake test task or `TEST_METADATA` entry is needed. Change `--seed` for another
reproducible campaign. The generators use their own seeded `Random`, without
changing the process-wide random generator.

Replay the checked-in corpus without external gems:

```sh
ruby spec/support/fuzz/replay.rb spec/support/fuzz/corpus/*
```

For a reproducible failure, preserve the minimized input as a corpus file and
add an explanatory regression test. The shared target and replay utility remain
available for the planned Ruzzy integration.

## Run mutation analysis

Mutation testing changes production code temporarily, one change at a time, and
runs the tests against each version. Failing tests detect the change; passing
tests leave a survivor to investigate. A survivor can reveal a missing assertion
or a behavior-preserving change. A timeout means no completed test verdict was
obtained; a setup error means the tool failed to evaluate the change. These are
different outcomes, and none is a count of bugs in the unmodified library.

Use MRI Ruby 3.4+; this POC was executed on Ruby 4.0.1/macOS ARM64.
Mutineer is included in the main Gemfile's `:check` group on supported MRI
versions, so older Ruby bundles can still install their test dependencies.

```sh
bundle install
sh bin/mutation.sh
```

The script runs the unmodified test suite first and propagates failure. Mutineer
writes `tmp/mutation/mutineer.json`. The script currently **exits nonzero** because
survivors remain. This is expected POC output, not an installation failure.
No survivors are suppressed or approved as a permanent baseline. The CI job
enforces the 100% threshold and propagates the runner's nonzero exit status.

The [property and mutation workflow](../.github/workflows/test-properties-and-mutations.yml)
runs on pull requests targeting `main`, pushes to `main`, and manual dispatch.
Two independent Ubuntu/Ruby 4.0 jobs use the main Gemfile and compile the native
extension. The property job runs the interval, property/corpus, and diff specs
with seed `20260918`. The Mutineer job runs the script above and uploads
`tmp/mutation/mutineer.json` as `mutineer-report` even when analysis fails.
There is no `continue-on-error`: the current mutation results fail the job.
Repository branch-protection settings are not changed by this workflow.

Classify survivors and decide which observable contracts to enforce. Preserve
errors and timeouts separately from assertion failures; Mutineer's score excludes
timeouts, so 100% alone does not establish a verdict for every mutation.

## Planned coverage-guided fuzzing with Ruzzy

Ruzzy is the chosen tool for the next phase. Its integration is currently removed;
there is no Ruzzy job or supported Ruzzy command in the current POC. Its AGPL
license is acceptable for the planned work.

Coverage-guided fuzzing evolves inputs using execution feedback to reach new
paths. Assertions and independent models must still define what constitutes a
wrong result; a Ruby implementation that silently makes an unsafe skip decision
may never crash. Reuse deterministic targets, seed them with representative and
boundary inputs, and preserve interesting inputs in a corpus.

Planned campaigns should have bounded time/memory, retained failing inputs, and
a replay path. Minimize reproducible failures and promote them into ordinary
regression tests. Compare instrumented and uninstrumented replay when diagnosing
runner failures. Native fuzzing will additionally need instrumented extension
builds; Ruby branch feedback alone does not establish native memory safety.

## Measured results

The mutation runner writes its machine-readable report to
`tmp/mutation/mutineer.json`. Run results are local artifacts ignored by Git.

Baseline: 55 existing interval examples, all passing. Expanded interval suite:
59 examples. Including the diff parser's existing tests: **80 examples passed**.

| Run | Mutations | Detected by test failure | Survived | Timed out |
| --- | ---: | ---: | ---: | ---: |
| Mutineer, existing tests | 48 | 35 | 10 | 3 |
| Mutineer, expanded tests | 48 | 36 | 9 | 3 |

Mutineer reports 77.8% → 80.0%, excluding the three timeouts from its score.
No run establishes a bug-free component.

Removing `build! unless @built` from `overlaps?` survived the original tests.
Adding `[10, 15]`, then `[1, 5]`, then querying `[1, 1]` demonstrates the missing
contract. The generated suite kills that mutation; a deterministic regression
now protects it too. This is a confirmed test gap, not a defect found in the
unmodified implementation.

The nine remaining survivors concern initial cache state, eliminating redundant
rebuilding guards, processing the first interval twice, and `build!` return
values. The RBS declares `build!` as returning `void`; asserting particular
booleans solely to improve the score would invent a contract. Caching and
synchronization changes need performance/concurrency assessment rather than
being dismissed as globally equivalent. All survivors remain visible.

The interval and property examples also passed on Ruby 2.7.8 in isolation, using
PropCheck 1.0.2 and the installed RSpec without the global instrumentation helper.
The shared oracle has its own RBS definition and Steep target. Full integration
and runtime matrix testing was not run. The main bundle follows dd-trace-rb
master; exact reproducibility requires preserving the dependency lockfile,
Ruby version, tool versions and seed.

## Rollout

1. Keep normal functional/compatibility CI, static checks, packaging validation,
   native stress tests and Memcheck as the foundation. Verify actual execution
   rather than treating skipped checks as clean analyses.
2. Introduce targeted mutation testing for critical logic and changed methods.
3. Expand property-based testing across input spaces and state transitions,
   promoting minimized failures into deterministic regression tests.
4. Add Ruzzy coverage-guided fuzzing in the next phase; evaluate native sanitizer
   testing separately and retain application performance measurements.

Promote specific, reviewed contracts to required gates after understanding their
failure modes and costs, instead of adopting an arbitrary repository-wide score.
