# Developing

This guide covers some of the common how-tos and technical reference material for developing changes within the CI visibility library.

## Table of Contents

- [Setting up](#setting-up)
- [Testing](#testing)
  - [Writing tests](#writing-tests)
  - [Running tests](#running-tests)
  - [Checking test coverage](#checking-test-coverage)
- [Checking code quality](#checking-code-quality)

## Setting up

*NOTE: To test locally, you must have `Docker` and `Docker Compose` installed. See the [Docker documentation](https://docs.docker.com/compose/install/) for details.*

The CI visibility library uses Docker Compose to create a Ruby environment to develop and test within, as well
as containers for any dependencies that might be necessary for certain kinds of tests.

To start a development environment, choose a target Ruby version then run the following:

```bash
# In the root directory of the project...
cd ~/datadog-ci-rb

# Create and start a Ruby 3.2 test environment with its dependencies
docker-compose run --rm datadog-ci-3.2 /bin/bash

# Then inside the container (e.g. `root@2a73c6d8673e:/app`)...
# Install the library dependencies
bundle install

# Install build targets
bundle exec appraisal install
```

Then within this container you can [run tests](#running-tests), [check code quality](#checking-code-quality), or
[run static typing checks](/docs/StaticTypingGuide.md).

## Testing

The test suite uses [RSpec](https://rspec.info/) tests to verify the correctness of both the core trace library and its integrations.

### Writing tests

New tests should be written as RSpec tests in the `spec/ddtrace` folder. Test files should generally mirror the structure of `lib`.

All changes should be covered by a corresponding RSpec tests. Unit tests are preferred, and integration tests are accepted where appropriate (e.g. acceptance tests, verifying compatibility with datastores, etc) but should be kept to a minimum.

#### Considerations for CI

All tests should run in CI. When adding new `spec.rb` files, you may need to add a test task to ensure your test file is run in CI.

- Ensure that there is a corresponding Rake task defined in `Rakefile` under the `spec` namespace, whose pattern matches your test file.
- Verify that this task is in the `TEST_METADATA` hash in `Rakefile`.

### Running tests

Simplest way to run tests is to run `bundle exec rake ci`, which will run the entire test suite, just as CI does.

#### For the core library

Run the tests for the core library with:

```bash
bundle exec rake test:main
```

#### For integrations

Integrations which interact with dependencies not listed in the `datadog-ci` gemspec will need to load these dependencies to run their tests.

To get a list of the spec tasks run `bundle exec rake -T 'test:'`

To run any of the specs above run `bundle exec rake 'test:<spec_name>'`.

For example: `bundle exec rake test:minitest`

#### Passing arguments to tests

When running tests, you may pass additional args as parameters to the Rake task. For example:

```bash
# Runs minitest integration tests with seed 1234
$ bundle exec rake test:minitest'[--seed 1234]'
```

This can be useful for replicating conditions from CI or isolating certain tests.

#### Checking test coverage

You can check test code coverage by creating a report *after* running a test suite:

```bash
# Run the desired test suite
$ bundle exec rake test:rspec
# Generate report for the suite executed
$ bundle exec rake coverage:report
```

A webpage will be generated at `coverage/report/index.html` with the resulting report.

Because you are likely not running all tests locally, your report will contain partial coverage results.
You *must* check the CI step `coverage` for the complete test coverage report, ensuring coverage is not
decreased.

## Checking code quality

This library uses [standardrb](https://github.com/standardrb/standard) to enforce code style and quality.

To check, run:

```bash
bundle exec standardrb
```
