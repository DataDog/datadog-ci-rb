# Datadog CI Visibility for Ruby

Datadog's Ruby Library for instrumenting your test and continuous integration pipeline. Checkout to learn more at our [official website](https://docs.datadoghq.com/continuous_integration/tests/ruby/?tab=azurepipelines).

## Installation

Add to your Gemfile.

```ruby
group :test do
  gem "datadog-ci"
end
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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Static typing

See [static typing guide](docs/StaticTypingGuide.md).

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/Datadog/datadog-ci). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Datadog/datadog-ci/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the `Datadog::CI` project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Datadog/datadog-ci/blob/main/CODE_OF_CONDUCT.md).
