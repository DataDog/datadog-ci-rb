# CRuby context and coverage investigation

The [test execution model](TestExecutionModel.md) selects sequential framework execution on one fiber per process, with process-wide coverage of application work. This investigation explains that decision; the defects below describe the previous implementation.

## CRuby and threaded tests

The GVL prevents simultaneous Ruby execution within one Ractor, but threads interleave and blocking operations release the GVL. It does not make a sequence of context and collector operations atomic. `Thread.current[:key]` is fiber-local and is not inherited by child threads or fibers. [CRuby extension documentation](https://docs.ruby-lang.org/en/master/extension_rdoc.html), [Thread documentation](https://docs.ruby-lang.org/en/3.4/Thread.html).

Minitest has a threaded executor, and Rails exposes it through `parallelize(..., with: :threads)`. These are usable on CRuby; Puma's tests provide a public example. This establishes usage, not its prevalence among our customers. [Minitest source](https://github.com/minitest/minitest/blob/master/lib/minitest/parallel.rb), [Rails guide](https://guides.rubyonrails.org/testing.html#parallel-testing-with-threads), [Puma tests](https://github.com/puma/puma/blob/main/test/test_integration_pumactl.rb).

Sequential tests also exercise application concurrency: Capybara can run its server in another thread, and applications use worker pools. Restricting framework execution therefore cannot justify collecting only the test thread. [Capybara documentation](https://github.com/teamcapybara/capybara#selenium).

## Reproduced defects

Deterministic queue/fiber schedules on CRuby 4.0.1 reproduced these failures:

| Previous behavior | Failure | Resolution |
| --- | --- | --- |
| Stop removed every matching line callback | One collector stopped another's hook, losing later dependencies. | Remove hooks by callback and collector data. |
| Fiber-local collectors shared one pending setup ID | A foreign worker flushed the wrong collector; subsequent tests lost setup dependencies. | One collector and sequential lifecycle per component. |
| Collector cached in `Thread.current` | Replacement components reused old ignored-path and threading settings. | Component-owned collector. |
| Block finalization followed only normal return | Customer exceptions bypassed coverage/retry cleanup. | Finalize in `ensure`. |
| Finish deactivated the caller's current test | A foreign or stale finish could finalize another attempt. | Validate execution owner and test identity. |

Single-thread coverage also omits joined child/pool work and does not isolate sibling fibers. Global coverage attributes detached work to whichever collection window is active. Neither is solved by adding locks alone.

We considered concurrent global windows and explicit propagation of attempt ownership. Global windows over-collect during overlap; precise ownership requires propagation through jobs, requests, existing pools, and fibers. Both still need a policy for work outliving its test. The selected sequential contract avoids that complexity while preserving application background coverage.
