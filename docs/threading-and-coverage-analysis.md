# CRuby context and coverage investigation

Investigation date: 2026-09-18. This records the original investigation, before the redesign. Experiments used CRuby 4.0.1 on arm64 macOS and the repository's Minitest 5 and 6 appraisals. The reproduced defects below describe the previous implementation.

**Accepted decision:** support sequential test execution on one owning Ruby fiber per process, and exclude threaded and fiber-based test executors from the support contract. Continue collecting coverage from application background threads and fibers. Supported process-based runners remain compatible. The [test execution model](TestExecutionModel.md) defines the contract and implemented enforcement; it supersedes the initial recommendation to retain threaded test visibility and disable only automatic skipping. The redesign replaces fiber-local caches with component-owned state, rejects unsupported lifecycle calls, and fixes collector-local hook removal and exception cleanup.

The alternatives below explain what supporting concurrent test execution would require. They are retained as investigation results, not as the selected implementation plan. Adding locks alone, or changing the default to single-thread coverage, cannot solve attribution.

## What CRuby guarantees

Ordinary Ruby threads share memory and interleave execution. Within one Ractor, the GVL prevents simultaneous execution of Ruby code; blocking operations and C extensions that release the GVL allow other threads to run. Consequently, I/O-heavy threaded tests can be useful on CRuby even though pure Ruby CPU work does not execute simultaneously within that Ractor. A Ruby-level sequence such as “take context ID, stop collector, store coverage, start next collector” is not made atomic by the GVL. [CRuby extension documentation](https://docs.ruby-lang.org/en/master/extension_rdoc.html), [Ractor documentation](https://docs.ruby-lang.org/en/3.4/ractor_md.html).

Avoid reasoning in terms of one permanent OS thread per Ruby thread across every supported version. Ruby 3.3 introduced an optional M:N scheduler, disabled by default in the main Ractor at that release. The stable identities relevant to this library are Ruby Thread, Fiber, and test attempt. This investigation does not establish Ractor support. [Ruby 3.3 release notes](https://www.ruby-lang.org/en/news/2023/12/25/ruby-3-3-0-released/).

`Thread.current[:key]` is **fiber-local**. A child thread or a newly created fiber does not inherit that value. `thread_variable_get/set` would share it among fibers of one thread, but would still not propagate it into another thread. Replacing one storage API with the other would change semantics rather than solve attribution. [Ruby Thread documentation](https://docs.ruby-lang.org/en/3.4/Thread.html).

Our native line/allocation callbacks operate under CRuby's normal execution constraints; they do not release the GVL themselves. For ordinary threads in one Ractor, concurrent C hash mutations are therefore not the main demonstrated problem. The failures below are ownership, scope, and lifecycle failures, reproducible with a deterministic schedule. Passing the GC stress case is useful evidence, not proof of memory safety across all Ruby versions or Ractors.

## Which test workloads use threads?

Among our principal framework integrations, Minitest is the direct built-in threaded executor. Rails exposes that same executor through `parallelize(..., with: :threads)`. Rails normally uses processes on CRuby, but threads are an explicit supported choice, not a JRuby-only feature. This establishes capability, not customer adoption rates. [Rails testing guide](https://guides.rubyonrails.org/testing.html#parallel-testing-with-threads), [Minitest executor source](https://github.com/minitest/minitest/blob/master/lib/minitest/parallel.rb).

“Nobody uses it on CRuby” is contradicted by public source: Puma's `TestIntegrationPumactl` calls `parallelize_me!`, and some tests in that class explicitly skip JRuby and TruffleRuby. We should not infer how common it is among our customers from this one example. [Puma tests](https://github.com/puma/puma/blob/main/test/test_integration_pumactl.rb).

RSpec and Cucumber commonly gain parallel execution through separate processes; `parallel_tests` explicitly partitions work into processes. That does not establish that no custom threaded runner exists. More importantly, even a sequential RSpec/Cucumber/Minitest runner can exercise a Capybara application server, database concurrency, an executor pool, or a test-created thread. Capybara documents drivers that run their server in another thread. Dropping support for concurrent *tests* does not remove the need to observe concurrent *application work*. [parallel_tests](https://github.com/grosser/parallel_tests), [Capybara](https://github.com/teamcapybara/capybara#selenium).

## Scope and ownership before the redesign

| State | Actual scope | Consequence |
| --- | --- | --- |
| Active test | Fiber-local key `:datadog_ci_active_test` | Concurrent worker tests can be isolated; child threads/fibers see no active test. |
| Session, module, suite registry | Shared process store, guarded by a reentrant Monitor | Workers share hierarchy; same-name suite creation is serialized. |
| Suite status, expected tests, retry statistics | Shared suite object with Monitor | Common Minitest completion bookkeeping has synchronization. |
| Native collector cache | Fiber-local key `:dd_coverage_collector` | Separate fibers normally obtain separate collectors, but every component instance in a fiber shares the same cache entry. |
| Default `:multi` line and allocation hooks | Observe all ordinary threads while active | Coverage follows a time window, not test ownership. |
| `:single` line hook | Starting Ruby thread, including its fibers | Excludes child/pool threads; does not isolate sibling fibers. Allocation tracing is unavailable. |
| Pending RSpec context ID | One component-wide ID, separately mutex-protected | Can be consumed by a worker using a different collector. |
| Saved RSpec context coverage | Component-wide map, mutex-protected | Protects hash access, but does not make the surrounding collection transaction correct. |

Relevant implementation: `Store::FiberLocal` (replaced by [execution store](../lib/datadog/ci/test_tracing/store/execution.rb)), [process store](../lib/datadog/ci/test_tracing/store/process.rb), [TIA component](../lib/datadog/ci/test_impact_analysis/component.rb), [native collector](../ext/datadog_ci_native/datadog_cov.c).

The naming is easy to misinterpret: `:multi` means “observe all threads,” not “isolate concurrent tests.” `:single` means “observe one Ruby thread,” not “the application has only one thread.” The component's single-thread option also disables RSpec context-coverage collection and merging.

## Failures reproduced before the redesign

1. **Stopping A disables B's line collection.** A and B start independent global collectors; B executes one dependency; A stops; B executes another dependency. B's result is missing the second file. `rb_remove_event_hook(on_line_event)` removes matching callbacks without restricting the removal to A's data. An idle collector's `stop` can do the same. Single-mode collectors on sibling fibers have the equivalent problem with thread hook removal. Allocation hook removal already uses the collector's data and passes the analogous survival test. [Native stop](../ext/datadog_ci_native/datadog_cov.c).

   The real Minitest executor reproduces this in both major versions: the first test's reporter callback releases the still-running second test, which then executes a unique source file. Both tests pass and retain their own test identities, but the second test's coverage omits the file. This can produce unsafe future skipping, not merely extra dependencies.

2. **A worker steals another worker's pending setup context.** A begins context coverage and executes setup. B starts a test, consumes the shared pending context ID, and stops B's own collector. A subsequently runs two tests in that context. Its first test can still contain setup accidentally because A's native buffer was never drained; the later test loses setup. The test explicitly checks the later test, avoiding a false sense of correctness from the first one. This is a component-level scenario relevant to any future concurrent context runner; it is not a claim that stock RSpec executes example groups in threads. [Context flush](../lib/datadog/ci/test_impact_analysis/component.rb).

3. **Reused workers retain old component configuration.** A component initializes coverage, then a replacement component uses the same worker. Its new single-thread setting or ignored path is ignored because the fiber-local cache contains the first component's collector. Both configuration changes have independent reproducers. This is a reconfiguration/ownership defect, not something that requires simultaneous execution. [Collector cache](../lib/datadog/ci/test_impact_analysis/component.rb).

4. **Exceptional block exit bypasses finalization.** The active-test fiber store correctly clears itself in `ensure`, but `TestTracing::Component#trace_test` calls `on_test_finished` only after a normal block return. A worker's customer exception is preserved, yet the coverage/retry/telemetry lifecycle is not finalized. An unfinished collector can keep observing work after the failed attempt. This concerns exceptional unwinding of the tracing API, not ordinary assertion failures already caught by a framework. [Block trace lifecycle](../lib/datadog/ci/test_tracing/component.rb).

5. **Foreign-thread finish deactivates the wrong test.** If A's test object is finished on worker B while B has its own active test, `Test#finish` deactivates B's active test through the component. It does not identify A as the object to deactivate. Normal Minitest execution finishes on the owning worker, so this is an adversarial public-API boundary rather than a demonstrated normal framework path. It needs an ownership contract and graceful handling. [Test finish](../lib/datadog/ci/test.rb), [deactivation](../lib/datadog/ci/test_tracing/component.rb).

There are also limitations that are **not races**: single mode misses a joined child thread; it includes unrelated sibling-fiber execution; and default mode assigns a delayed background job to whatever collection window is active when the job executes. The new characterization tests deliberately pass while demonstrating these limits. Independent global collectors also collect other tests' work during overlap. Such over-collection usually costs skipping efficiency; missing dependencies is the more serious correctness failure.

## What passed, and what existing tests missed

The original tests verified isolation of active tests across reused workers, shared hierarchy IDs, cleanup of fiber-local state after exceptions, and absence of implicit child-thread/fiber propagation. Native single-mode workers retain exact independent file sets over eight synchronized collection rounds with GC and compaction between execution phases. Rejecting a foreign-thread native `stop` leaves the owner's collector working. Allocation collection continues after a different collector stops. The original Minitest overlap scenario passed in single mode; the redesigned integration rejects that executor in both coverage configurations.

Existing tests mostly exercised either one global collector with background threads or separate single-mode collectors. Those are different contracts from two overlapping global collectors. Checking that coverage is nonempty would also miss the late-file loss: earlier dependencies and the test source still make the event look plausible. Our new source-specific assertions test completeness, not just event existence.

All coordinated scenarios use queues or fiber suspension. Fork isolation contains native hook leaks and bounds deadlocks through the existing ten-second test helper. Tests call real collectors and framework executors; no production classes are reopened or prepended, and no instance-variable introspection was added. Mocks observe component events/reporting without replacing native collection.

The initial investigation added nineteen examples: nine pending regressions for confirmed defects and ten passing characterization cases. The redesign replaces concurrent-executor attribution assertions with safe-rejection tests and converts the collector defects into passing regressions. The current test files contain no pending markers for these defects. Ruby changes have corresponding RBS updates.

## Hardening requirements and alternatives considered

First, fix collector-local lifecycle independently of policy. Remove hooks by callback **and collector data**, for both global and thread hooks; CRuby exposes the corresponding APIs. Track whether line collection is active, make repeated start/stop behavior explicit, retain the owning Ruby thread, and prevent a foreign stop from damaging any collector. Validate API availability across the supported CRuby matrix. The existing data-qualified allocation removal is a useful precedent. [CRuby debug API](https://docs.ruby-lang.org/capi/en/master/db/d16/debug_8h.html).

Next, bind state to a component generation and a test-attempt token. Cache the collector with its owning component, put pending context IDs and their collectors in the same execution state, and finalize that state exactly once in `ensure`. A retry needs a new attempt token even when it reuses the thread and logical test name. Instrumentation cleanup must log internal failures and preserve the original customer exception. Cross-thread finish should either use an explicit ownership-aware operation or warn and leave the unrelated active test alone.

The accepted decision selects sequential tests per process with global coverage. The alternatives considered were:

| Policy | Benefit | Limit |
| --- | --- | --- |
| Sequential tests per process, global coverage | Captures joined child threads and pre-existing server/pool workers | Work that outlives its test still needs handling. |
| Concurrent tests, own-thread-only coverage | Simple worker isolation | Incomplete for child threads, application servers, allocation-only dependencies, and current context coverage. Unsafe as a silent default. |
| Concurrent tests, conservative global windows | Attribute observed files to every active test/window; avoids missing overlapping work after lifecycle fixes | More dependencies and less skipping; delayed jobs still require ownership or invalidation. |
| Explicit propagated test-attempt ownership | Can attribute asynchronous work precisely | Needs job enqueue/dequeue and request boundaries, not just `Thread.new`; must handle existing pools, fibers, detached jobs, cancellation, and late completion. |

A single process-level native dispatcher with an active-window registry could implement conservative concurrent coverage with one line hook and one allocation hook. Stopping a test would unregister its window rather than remove the shared hook. This also avoids repeated global callbacks for every active collector. This alternative was not selected, implemented, or benchmarked; the accepted model needs only one active test window. The internal allocation callback must retain its restrictions on allowed Ruby APIs.

Conservative windows are sound only for work completed while the relevant test remains registered. If ownership is unknown or work outlives the test, invalidate that test's optimization eligibility or explicitly retain its window until known tasks finish. Merely observing `Thread.list` cannot detect this reliably: instrumentation itself uses threads, and application workers can exist before any test starts. Detect executor capability and overlapping test lifecycles instead.

Additional review risks remain outside the reproduced cases: suite-level collection started and finished on different workers, duplicate suite-start side effects outside registry locking, and shutdown while workers still finish suites. In particular, process-store shutdown holds its Monitor while finishing suites, whereas suite finish holds its own Monitor before entering the process store. That lock-order inversion warrants a separate shutdown test. Ordinary executor shutdown joins workers, so it should not be presented as an observed normal-run deadlock.

Validate enforcement and the supported sequential model across CRuby 2.7–4.0, both Minitest majors where supported, and a real pre-existing application pool. Concurrent-executor cases should verify safe rejection rather than become a commitment to concurrent attribution. Add cancellation, nested setup contexts, suite-level mode, retries, and late asynchronous completion to the acceptance criteria. This investigation does not establish Ractor support or validate separate-process coverage by implication.

## Original investigation validation

| Check | Result |
| --- | --- |
| Native extension build, CRuby 4.0.1 | Passed |
| DDCov, test tracing, and TIA suites | 545 examples, 0 failures, 8 expected pending regressions |
| Complete Minitest 6 integration directory | 79 examples, 0 failures, 1 expected pending regression |
| New Minitest 5 executor cases | 2 examples, 0 failures, 1 expected pending regression (same scenario as Minitest 6) |
| StandardRB | 503 files inspected, no offenses |
| ArchSpec | Passed; 238 files checked, no violations; existing analysis gaps remain |
| Steep | No type errors |

The first broad run was blocked by sandbox restrictions on DRb Unix sockets; the same command passed outside the sandbox. RuboCop's cache was redirected to a writable temporary directory. These were environment restrictions, separate from the reproduced product defects. No full all-framework suite was run and no files were staged, committed, or pushed.

From the repository root:

```sh
bundle exec rake compile_ext
bundle exec rspec spec/ddcov spec/datadog/ci/test_tracing spec/datadog/ci/test_impact_analysis --format progress
BUNDLE_GEMFILE=gemfiles/ruby_4.0_minitest_6.gemfile bundle exec rspec spec/datadog/ci/contrib/minitest --format progress
BUNDLE_GEMFILE=gemfiles/ruby_4.0_minitest_5.gemfile bundle exec rspec spec/datadog/ci/contrib/minitest/concurrency_spec.rb --format progress
RUBOCOP_CACHE_ROOT=/private/tmp/datadog-ci-concurrency-rubocop bundle exec standardrb
bundle exec rake archspec
bundle exec rake steep:check
```

The historical pending results above are retained as evidence of the investigation. For the implemented storage model, enforcement behavior, and current regression coverage, see [Test execution model](TestExecutionModel.md). The framework adversarial cases now assert rejection and continued customer-test execution; they no longer assert support for concurrent test attribution.
