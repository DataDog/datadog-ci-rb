# File dependencies for test impact analysis

When TIA coverage collection is enabled, files opened through supported Ruby APIs
are included alongside executed Ruby files in the existing `citestcov` payload.
This captures fixtures, templates, JSON, YAML, and other non-Ruby inputs without a
new backend schema or configuration option. Only filenames are reported.

The approach follows the dependency signal described in
[Stripe's selective test execution article](https://stripe.dev/blog/selective-test-execution-at-stripe-fast-ci-for-a-50m-line-ruby-monorepo).
Stripe intercepts operating-system opens with an injected shared library. This
implementation intercepts Ruby APIs and does not inject a library into subprocesses.

## Supported operations

- `File.open`, `File.new`, `Kernel.open`, and `File#reopen` are observed after a
  successful open, before the caller's block runs.
- `File` and `IO` class methods `read`, `binread`, `readlines`, `foreach`, `sysopen`,
  `write`, and `binwrite` record the requested path before the operation. This
  conservatively includes failed attempts and files written by tests.
- APIs that delegate to these methods, including `Pathname` reads and common
  JSON/YAML fixture loaders, are covered as well.
- Lazy `foreach` enumerators record a dependency when consumed, rather than when
  created. Encoding options, blocks, return values, and customer IO errors are
  forwarded. Path-like objects are coerced once.
- Command strings passed to pipe-capable `IO` APIs and numeric file descriptors
  are not treated as filenames.

## Paths and attribution

Paths are made absolute using the working directory at access time; literal
`~` characters are not expanded. Both the opened name and its resolved symlink
target are considered. Targets are resolved on each access so a symlink changed
during a test can contribute both targets. Existing serialization converts these
paths to repository-relative names.

Only paths within the repository root are retained. The existing bundled-gem
directory exclusion applies, with directory boundaries checked for both the root
and excluded directory. Repeated accesses are deduplicated within each collection
window.

File dependencies use the same collection windows as Ruby dependencies: individual
tests, entire suites in suite-skipping mode, and inherited RSpec context setup.
Skipped tests discard their coverage. Session-wide setup attribution is handled
separately from these test, suite, and context collection windows.

Default multi-threaded mode captures background-thread accesses. Single-threaded
mode attributes accesses only to the thread running that test, including its
fibers. Components own their collectors and release them at shutdown. An inherited
test collector does not attribute new child-process reads until collection is
started in that process. Child coverage is not automatically merged back into the
parent process.

Tracking failures are logged at warning level without replacing the result or
exception of the customer's IO operation. A recursion guard prevents logging IO
from recursively recording dependencies.

## Limits and cost

This is file-open tracking, not a complete filesystem dependency graph. It does
not observe native-library opens, spawned subprocesses, `IO.copy_stream`'s internal
opens, `ARGF`, metadata checks such as `File.exist?`, directory enumeration/globbing,
or reads from handles opened before the collection window. Ruby `require`/`load`
dependencies continue to use the existing Ruby coverage mechanisms. A newly added
file can affect directory-discovery tests without having a prior dependency;
those tests still need an explicit unskippable policy or custom impacted files.

Hooks are installed on first collection. When inactive they forward directly,
without path coercion or filesystem inspection. Active tracking adds path
normalization, symlink resolution, and a synchronized hash insertion; repeated
opens reuse the hash entry but still resolve symlinks for correctness.

Run the standalone tiny-fixture microbenchmark in a fresh process:

```sh
bundle exec ruby benchmarks/test_impact_analysis_file_access.rb 10000
```

It compares uninstrumented, installed-but-inactive, and active reads, reporting
median time and allocations over five samples. Local Ruby 3.4.5 measurements on
macOS were approximately 29.6, 28.1, and 40.3 microseconds per read, with 3, 5, and
8 allocations respectively. These filesystem timings are noisy and represent a
tiny-file worst case, not an estimate of whole-suite overhead.
