# Test execution model

Status: implemented in this branch, 2026-09-18. This describes the new execution contract and runtime enforcement; it does not describe older releases.

## Decision

The library officially supports CRuby. Within each process, all test attempts and framework lifecycle hooks must execute sequentially on one owning Ruby fiber. A fiber belongs to one Ruby thread, so this also establishes one test-execution thread per process. The owner need not be the main thread or its root fiber, but it must remain the same throughout the test run in that process.

The contract covers test bodies, retries, setup and teardown, shared context hooks, and test/suite lifecycle operations. Sequentially handing tests between different threads or fibers is also unsupported, even if the tests never overlap. Nested test attempts are unsupported.

Threaded test executors, including Minitest's parallel executor and Rails' `parallelize(..., with: :threads)`, are outside this support boundary. Fiber-based test executors that distribute tests across fibers are also unsupported. Parallel execution through supported process-based runners remains compatible: each worker process has its own owner and sequential test lifecycle.

## Application concurrency remains supported

Tests may exercise application code that uses additional threads and fibers, including application servers, existing worker pools, and threads created by a test. Instrumentation may also use background threads. The restriction applies to execution of the test framework's lifecycle, not to the number of threads in the process.

Coverage must continue observing application work across threads and fibers during the active test or setup window. The legacy `itr_code_coverage_use_single_threaded_mode` option is accepted for compatibility but ignored with a warning. Coverage always observes all application threads; enabling this option no longer disables allocation tracing or shared-context coverage.

For correct attribution, a test must wait for its relevant asynchronous application work to finish before its lifecycle ends. Work that outlives the test cannot reliably be attributed by a process-wide collection window. Supporting detached work across test boundaries would require a separate ownership mechanism and is outside this decision.

## Rationale and architecture

CRuby's GVL does not make a multi-step test or coverage lifecycle atomic. The investigation reproduced missing dependencies when overlapping collectors stopped, mismatched ownership of shared setup coverage, and incorrect finalization across workers. Precise attribution between concurrent tests would require propagation through application threads, fibers, jobs, and requests. We choose a smaller execution contract instead of maintaining that additional model.

The architecture has one active test attempt, one component-owned coverage collector observing the process, and one sequential context-coverage lifecycle per process. The active-test API remains scoped to the owning fiber; observing a background thread's coverage does not implicitly give it ownership of the active test. Session and suite state remain available as needed for process-based runners.

This decision does not remove the need for reliable exception cleanup, configuration replacement, collector lifecycle management, or ownership checks when finishing a test. Those problems can occur independently of a threaded executor. See the [context and coverage investigation](threading-and-coverage-analysis.md) for the evidence and alternatives considered.

## Storage and collection lifecycle

The composition root injects the same `Utils::TestExecution` instance into test tracing and test impact analysis. Its first lifecycle transition establishes the owning fiber. A reentrant monitor protects instrumentation transitions and coordinates rejection of foreign calls; it is never held while a customer test body executes. Application threads therefore remain free to run, and a foreign lifecycle call can disable collection without waiting for the current test to finish.

`Store::Execution` holds the active test in an instance field and exposes it only on the owning fiber in the owning process. No active-test or collector state is cached in `Thread.current`. A replacement component gets fresh state and honors its own coverage configuration. Session/module/suite registries retain their synchronization because process runners access coordinator metadata through DRb. Remote suite completion is coordinator bookkeeping, so it does not transfer ownership of test execution.

The TIA component owns its collector, pending setup-context ID, and saved setup coverage together. The transitions are:

| Transition | Coverage action |
| --- | --- |
| Begin shared setup | Flush previous setup coverage under its context ID; start the next setup window. |
| Begin a test attempt | Flush pending setup; start the test window. |
| Finish a test attempt | Stop collection; merge saved setup from the test's context chain; publish coverage unless skipped or disabled. |
| Clear a context | Stop and discard pending collection for that context, including contexts with no tests; remove saved coverage. |
| Disable instrumentation or shut down | Stop the collector and discard pending data without publishing it. |
| First lifecycle entry after fork | Discard inherited collector data and establish a new process-local execution owner. |

Every attempt uses a distinct test object. Finishing a test checks that identity before clearing context, and repeated finish calls cannot finalize a later attempt. Block tracing finalizes in `ensure`, including exception and cancellation paths. Initialization and finalization failures disable optimization with a warning while preserving customer execution and exceptions.

Native start/stop operations are idempotent, and hook removal identifies both the callback and the collector instance. Shutting down an old or idle collector cannot remove a replacement collector's hooks. The native implementation retains its low-level single-thread mode for compatibility tests, but Test Optimization always uses process-wide collection.

## Enforcement

Minitest preflight rejects classes using its threaded executor, including a mixed sequential/threaded run. Rails executor configuration is checked before it installs Minitest's parallel marker: that marker is also used by Rails process workers and cannot identify the execution model by itself. Direct Minitest test execution repeats the check for runners that bypass preflight. Lifecycle entry points also validate the owning fiber to catch custom runners, sequential worker handoffs, and foreign-fiber finish calls. Forked workers establish their own owner.

Unsupported execution must produce a clear warning and disable test instrumentation and optimization safely for that process. Customer tests must continue running. The library must not raise internal instrumentation errors, silently change the customer's executor, clear another fiber's active test, or publish incomplete coverage as valid optimization data. Already skipped tests cannot be recovered through late detection, which is why framework detection must precede skipping.

Thread counts are not a valid detection mechanism: supported application and instrumentation threads may already exist before tests start.

Adversarial regression tests exercise safe rejection of unsupported executors and lifecycle calls, configuration replacement, collector hook isolation, repeated finalization, exceptions, setup coverage, and fork isolation. Application-work tests verify collection from joined threads, fibers, and an existing worker pool. A passing concurrent-worker experiment does not extend the support contract.

## Validation

The redesign was checked on CRuby 4.0.1 with 594 core examples, the Minitest 5 and 6 integration suites, RSpec 3, Cucumber 11, and Rails 7 and 8 (including real thread and process executors). All passed without pending concurrency regressions. StandardRB, ArchSpec, and Steep passed. A separate native build and smoke test on CRuby 2.7.8 verified repeated start/stop, collector hook isolation, and background-thread coverage. The complete Ruby-version and framework-version matrix was not run locally.
