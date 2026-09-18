# Test execution model

## Support contract

This library supports CRuby. Each process must run test attempts and framework hooks sequentially on one owning Ruby fiber, which also fixes the test-execution thread. The owner need not be the main thread. Nested attempts and handoffs between threads or fibers are unsupported, even when sequential. Process-based parallel runners remain supported.

Application code may use background threads, fibers, servers, and existing worker pools. Coverage observes their work during the active test or setup window; the active-test API remains visible only on the owning fiber. Tests must wait for their relevant asynchronous work before finishing: detached work cannot be attributed reliably across test boundaries.

The legacy `itr_code_coverage_use_single_threaded_mode` setting is accepted but ignored with a warning. DDCov has no threading mode: it always observes application threads, allocation dependencies, and shared setup.

## Ownership and lifecycle

Tracing and test impact analysis share `Utils::TestExecution`. The first lifecycle transition establishes the owner. A reentrant monitor protects instrumentation transitions, never customer test bodies. Foreign lifecycle calls warn, disable optimization, and discard pending coverage while customer tests continue.

`Store::Execution` holds one active test in a component-owned field, visible only to its process and fiber. The TIA component owns one process-wide collector, its pending setup-context ID, and saved setup coverage. Replacement components get fresh state; the first collection transition after a fork discards inherited data and establishes a new owner.

| Transition | Coverage action |
| --- | --- |
| Begin shared setup | Save the preceding setup window and start the next. |
| Begin a test | Save pending setup and start the test window. |
| Finish a test | Stop collection, merge setup from its context chain, and publish unless skipped or disabled. |
| Clear a context | Stop pending collection for that context and remove its saved coverage, including empty contexts. |
| Disable or shut down | Stop collection and discard pending data. |

Finishing checks test identity before clearing context. Block tracing finalizes in `ensure`; repeated finishes cannot finalize a later attempt. Test initialization/finalization failures warn and disable optimization without replacing customer exceptions. Native start/stop is idempotent and removes hooks by collector identity, so one collector cannot disable another.

Session/module/suite registries retain synchronization for DRb coordinator access. Remote suite completion updates metadata and does not transfer test-execution ownership.

## Executor detection

Minitest preflight rejects threaded executors, including mixed runs. Rails configuration must be checked before its executor starts: Rails uses Minitest's parallel marker for both threads and processes. Direct test execution repeats detection for runners bypassing preflight, and runtime ownership checks catch custom thread/fiber runners. Thread counts cannot distinguish application workers from test workers.

The Minitest 6 `Minitest.run_one_method` compatibility method remains for Rails fork workers, retries, and suite completion. The removed `ParallelExecutorMinitest6` shim only patched Minitest's `Thread.new` pool. Known unsupported executors are detected before skipping; late detection cannot recover already-skipped tests.

See the [CRuby investigation](threading-and-coverage-analysis.md) for the rationale. Regression tests cover ownership violations, component replacement, exception cleanup, setup coverage, native hook isolation, application workers, and Rails fork retries.
