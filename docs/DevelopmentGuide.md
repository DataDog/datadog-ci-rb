# Developing

This guide covers some of the common how-tos and technical reference material for developing changes within the Test Optimization library.

## Table of Contents

- [Setting up](#setting-up)
- [Testing](#testing)
  - [Writing tests](#writing-tests)
  - [Running tests](#running-tests)
  - [Checking test coverage](#checking-test-coverage)
- [Checking code quality](#checking-code-quality)

## Setting up

_NOTE: To test locally, you must have `Docker` and `Docker Compose` installed. See the [Docker documentation](https://docs.docker.com/compose/install/) for details._

The Test Optimization library uses Docker Compose to create a Ruby environment to develop and test within, as well
as containers for any dependencies that might be necessary for certain kinds of tests.

To start a development environment, choose a target Ruby version then run the following:

```bash
# In the root directory of the project...
cd ~/datadog-ci-rb

# Create and start a Ruby 3.2 test environment with its dependencies
docker compose run --rm datadog-ci-3.2 /bin/bash

# Then inside the container (e.g. `root@2a73c6d8673e:/app`)...
# Install the library dependencies
bundle install

# Install build targets
bundle exec appraisal install
```

Then within this container you can [run tests](#running-tests), [check code quality](#checking-code-quality), or
[run static typing checks](/docs/StaticTypingGuide.md).

## Testing

The test suite uses [RSpec](https://rspec.info/) tests to verify the correctness of both the core library and its integrations with various test frameworks.

### Writing tests

New tests should be written as RSpec tests in the `spec/datadog/ci` folder. Test files should generally mirror the structure of `lib`.

All changes should be covered by a corresponding RSpec tests. Unit tests are preferred, and integration tests are accepted where appropriate (e.g. acceptance tests, verifying compatibility with datastores, etc) but should be kept to a minimum.

#### Considerations for CI

All tests should run in CI. When adding new `_spec.rb` files, you may need to add a rake task to ensure your test file is run in CI.

- Ensure that there is a corresponding Rake task defined in `Rakefile` under the `spec` namespace, whose pattern matches your test file. For example

```ruby
  namespace :spec do
    desc ""
    RSpec::Core::RakeTask.new(:foo) do |t, args|
      t.pattern = "spec/datadog/ci/contrib/bar/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end
```

- Ensure the Rake task is configured to run for the appropriate Ruby runtimes, by introducing it to our test matrix. You should find the task with `bundle exec rake -T test:<foo>`.

```ruby
TEST_METADATA = {
  "foo" => {
    # Without any appraisal group dependencies
    "" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3",

    # or with appraisal group definition `bar`
    "bar" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3",
  }
}
```

### Running tests

Simplest way to run tests is to run `bundle exec rake ci`, which will run the entire test suite, just as CI does.

#### For the core library

Run the tests for the core library with:

```bash
bundle exec rake test:main
```

#### For integrations

Integrations which interact with dependencies not listed in the `datadog-ci` gemspec will need to load these dependencies to run their tests. Each test task could consist of multiple spec tasks which are executed with different groups of dependencies (likely against different versions or variations).

To get a list of the spec tasks run `bundle exec rake -T 'test:'`

To run any of the specs above run `bundle exec rake 'test:<spec_name>'`.

For example: `bundle exec rake test:minitest`

#### Working with appraisal groups

Checkout [Apppraisal](https://github.com/thoughtbot/appraisal) to learn the basics.

Groups are defined in the `Apparisals` file and their names are prefixed with Ruby runtime based on the environment. `*.gemfile` and `*.gemfile.lock` from `gemfiles/` directory are generated from those definitions.

To find out existing groups in your environment, run `bundle exec appraisal list`

After introducing a new group definition or changing existing one, run `bundle exec appraisal generate` to propagate the changes.

To install dependencies, run `bundle exec appraisal install`.

In addition, if you already know which appraisal group definition to work with, you can target a specific group operation with environment vairable `APPRAISAL_GROUP`, instead of all the groups from your environment. For example:

```bash
# This would only install dependencies for `cucumber` group definition
APPRAISAL_GROUP=cucumber-8 bundle exec appraisal install
```

#### Passing arguments to tests

When running tests, you may pass additional args as parameters to the Rake task. For example:

```bash
# Runs minitest integration tests with seed 1234
$ bundle exec rake test:minitest'[--seed 1234]'
```

This can be useful for replicating conditions from CI or isolating certain tests.

#### Running one single test

Many times we want to run one test file or one single test instead of rerunning the whole test suite.
To do that, you could use `--example` RSpec argument.

For example, to run only tests for Minitest hooks you can do:

```bash
bundle exec rake test:minitest'[--example hooks]'
```

#### Checking test coverage

You can check test code coverage by creating a report _after_ running a test suite:

```bash
# Run the desired test suite
$ bundle exec rake test:rspec
# Generate report for the suite executed
$ bundle exec rake coverage:report
```

A webpage will be generated at `coverage/report/index.html` with the resulting report.

Because you are likely not running all tests locally, your report will contain partial coverage results.
You _must_ check the CI step `coverage` for the complete test coverage report, ensuring coverage is not
decreased.

## Checking code quality

This library uses [standardrb](https://github.com/standardrb/standard) to enforce code style and quality.

To check, run:

```bash
bundle exec standardrb
```

### Architecture checks

[ArchSpec](https://archspecrb.dev/) prevents code outside a Test Optimization component from referencing its internal constants. A component's `component.rb` and `null_component.rb` files are its public entry points; callers can use their public methods, while the remaining files in that component directory are private.

Run the architecture check on Ruby 3.2 or newer:

```bash
bundle exec rake archspec
```

Architecture violations fail the check and must be fixed by moving the interaction behind the owning component's public interface.

## Session dependencies for Test Impact Analysis

TIA sends shared setup dependencies as `citestcov` version 2 events with
`test_session_id` and `files`, omitting `test_suite_id` and `span_id`. This is the
same session-only shape used by the [JavaScript tracer's coverage encoder](https://github.com/DataDog/dd-trace-js/blob/master/packages/dd-trace/src/encode/coverage-ci-visibility.js).
Test and suite events keep their existing IDs and dependencies; the session event
is not a union of their coverage.

Collection starts after the runner creates/configures its session and stops before
the first suite, context hook, or test starts. During this window it records Ruby
method/block execution and file access. Repository and bundle-path filtering still
apply. An empty session produces no session coverage event, and finishing or
shutting down an unfinished session disables collection. Repeated starts of the
same session do not reset its dependencies; a new session starts fresh.

The shared set deliberately excludes execution and file access inside
`Kernel.require`, `require_relative`, and `load`. Merely loading a class, support
module, or fixture factory must not make it an input to every test. Already-loaded
project entry points `spec/spec_helper.rb`, `spec/rails_helper.rb`,
`test/test_helper.rb`, and `features/support/env.rb` are included explicitly.
Static require-graph expansion is not applied to session dependencies.

This boundary reflects common Ruby setups: [RuboCop's spec helper](https://github.com/rubocop/rubocop/blob/master/spec/spec_helper.rb)
loads cops and support files; [Discourse's Rails helper](https://github.com/discourse/discourse/blob/main/spec/rails_helper.rb)
loads support files and fabricators; [Rails enables eager loading in CI](https://github.com/rails/rails/blob/main/guides/source/testing.md#testing-eager-loading).
A loaded file is therefore not sufficient evidence of a shared dependency.

Forks inherit setup collected before the fork. Each process freezes and reports
its own setup fragment under the existing session ID. Fresh distributed workers
collect their own setup when they join the session. Threaded test execution starts
after shared collection is frozen; per-test/per-suite collectors retain their
existing attribution rules.

This is intentionally conservative. It does not reconstruct arbitrary boot-time
dependencies from before session startup, infer constant-only uses from loaded
classes, or treat teardown as shared setup. Custom helper filenames are covered
when their methods/blocks execute during shared setup, rather than by name alone.
No CI plan/run correlation tags are added.
