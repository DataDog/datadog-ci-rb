# Datadog CI Visibility for Ruby

[![codecov](https://codecov.io/gh/DataDog/datadog-ci-rb/branch/main/graph/badge.svg)](https://app.codecov.io/gh/DataDog/datadog-ci-rb/branch/main)
[![CircleCI](https://dl.circleci.com/status-badge/img/gh/DataDog/datadog-ci-rb/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/DataDog/datadog-ci-rb/tree/main)

Datadog's Ruby Library for instrumenting your test and continuous integration pipeline.
Learn more on our [official website](https://docs.datadoghq.com/continuous_integration/tests/ruby/).

> [!IMPORTANT]
> The `datadog-ci` gem is currently a component of [`ddtrace`](https://github.com/datadog/dd-trace-rb) and should not be used without it.
>
> We expect this to change in the future.

## Installation

Add to your Gemfile.

```ruby
gem "ddtrace"
```

## Usage

### RSpec

To activate `RSpec` integration, add this to the `spec_helper.rb` file:

```ruby
require 'rspec'
require 'datadog/ci'

Datadog.configure do |c|
  # Only activates test instrumentation on CI
  c.tracing.enabled = (ENV["DD_ENV"] == "ci")

  # Configures the tracer to ensure results delivery
  c.ci.enabled = true

  # The name of the service or library under test
  c.service = 'my-ruby-app'

  # Enables the RSpec instrumentation
  c.ci.instrument :rspec, **options
end

```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether RSpec tests should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `service_name` | Service name used for `rspec` instrumentation. | `'rspec'` |
| `operation_name` | Operation name used for `rspec` instrumentation. Useful if you want rename automatic trace metrics e.g. `trace.#{operation_name}.errors`. | `'rspec.example'` |

### Minitest

The Minitest integration will trace all executions of tests when using `minitest` test framework.

To activate your integration, use the `Datadog.configure` method:

```ruby
require 'minitest'
require 'datadog/ci'

# Configure default Minitest integration
Datadog.configure do |c|
  # Only activates test instrumentation on CI
  c.tracing.enabled = (ENV["DD_ENV"] == "ci")

  # Configures the tracer to ensure results delivery
  c.ci.enabled = true

  # The name of the service or library under test
  c.service = 'my-ruby-app'

  c.ci.instrument :minitest, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Minitest tests should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `service_name` | Service name used for `minitest` instrumentation. | `'minitest'` |
| `operation_name` | Operation name used for `minitest` instrumentation. Useful if you want rename automatic trace metrics e.g. `trace.#{operation_name}.errors`. | `'minitest.test'` |

### Cucumber

Activate `Cucumber` integration with configuration

```ruby
require 'cucumber'
require 'datadog/ci'

Datadog.configure do |c|
  # Only activates test instrumentation on CI
  c.tracing.enabled = (ENV["DD_ENV"] == "ci")

  # Configures the tracer to ensure results delivery
  c.ci.enabled = true

  # The name of the service or library under test
  c.service = 'my-ruby-app'

  # Enables the Cucumber instrumentation
  c.ci.instrument :cucumber, **options
end
```

`options` are the following keyword arguments:

| Key | Description | Default |
| --- | ----------- | ------- |
| `enabled` | Defines whether Cucumber tests should be traced. Useful for temporarily disabling tracing. `true` or `false` | `true` |
| `service_name` | Service name used for `cucumber` instrumentation. | `'cucumber'` |
| `operation_name` | Operation name used for `cucumber` instrumentation. Useful if you want rename automatic trace metrics e.g. `trace.#{operation_name}.errors`. | `'cucumber.test'` |

## Contributing

See [development guide](/docs/DevelopmentGuide.md), [static typing guide](docs/StaticTypingGuide.md) and [contributing guidelines](/CONTRIBUTING.md).

## Code of Conduct

Everyone interacting in the `Datadog::CI` project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](/CODE_OF_CONDUCT.md).
