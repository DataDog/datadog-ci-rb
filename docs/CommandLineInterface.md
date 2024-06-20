# Command line interface

This library provides experimental command line interface `ddcirb` to get the percentage of the tests
that will be skipped for the current test run.

## Usage

This tool must be used on the same runner as your tests are running on with the same ENV variables.
Run the command in the same folder where you usually run your tests. Gem datadog-ci must be installed.

Available commands:

- `bundle exec ddcirb skipped-tests` - outputs the percentage of skipped tests to stdout. Note that it runs your specs
in dry run mode, don't forget to set RAILS_ENV=test environment variable.
- `bundle exec ddcirb skipped-tests-estimate` - estimates the percentage of skipped tests and outputs to stdout without loading
your test suite and running it in dry run mode. ATTENTION: this is considerably faster but could be very inaccurate.

Example usage:

```bash
$ RAILS_ENV=test bundle exec ddcirb skipped-tests
0.45
```

Available arguments:

- `-f, --file` - output to a file (example: `bundle exec ddcirb skipped-tests -f out`)
- `--verbose` - enable verbose output for debugging purposes (example: `bundle exec ddcirb skipped-tests --verbose`)
- `--spec-path` - path to the folder with RSpec tests (default: `spec`, example: `bundle exec ddcirb skipped-tests --spec-path="myapp/spec"`)
- `--rspec-opts` - additional options to pass to the RSpec when running it in dry run mode (example: `bundle exec ddcirb skipped-tests --rspec-opts="--require rails_helper"`)

## Example usage in Circle CI

This tool could be used to determine [Circle CI parallelism](https://support.circleci.com/hc/en-us/articles/14928385117851-How-to-dynamically-set-job-parallelism) dynamically:

```yaml
version: 2.1

setup: true

orbs:
  continuation: circleci/continuation@0.2.0

jobs:
  determine-parallelism:
    docker:
      - image: cimg/base:edge
    resource_class: medium
    steps:
      - checkout
      - run:
          name: Determine parallelism
          command: |
            PARALLELISM=$(RAILS_ENV=test bundle exec ddcirb skipped-tests)
            echo "{\"parallelism\": $PARALLELISM}" > pipeline-parameters.json
      - continuation/continue:
          configuration_path: .circleci/continue_config.yml
          parameters: pipeline-parameters.json

workflows:
  build-setup:
    jobs:
      - determine-parallelism
```
