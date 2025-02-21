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
    "" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",

    # or with appraisal group definition `bar`
    "bar" => "✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby",
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
