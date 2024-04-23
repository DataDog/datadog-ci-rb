# Upgrading from ddtrace 1.x to datadog-ci

[Test visibility for Ruby](https://docs.datadoghq.com/tests/setup/ruby/) is no longer part of `datadog` gem and fully migrated to
`datadog-ci` gem. To continue using it after gem `datadog` v2.0 is released, do these changes.

## Add datadog-ci to your gemfile

Before:

```ruby
gem "ddtrace", "~> 1.0"
```

After:

```ruby
group :test do
  gem "datadog-ci", "~> 1.0"
end
```

Or if you use other Datadog products:

```ruby
gem "datadog", "~> 2.0"

group :test do
  gem "datadog-ci", "~> 1.0"
end
```

## Change WebMock or VCR configuration

New test visibility features (such as [intelligent test runner](https://docs.datadoghq.com/intelligent_test_runner/), git metadata upload, [code coverage support](https://docs.datadoghq.com/tests/code_coverage)) require some DataDog endpoints to be allowlisted by WebMock/VCR tools when using agentless mode.

For WebMock allow all requests that match datadoghq:

```ruby
WebMock.disable_net_connect!(:allow => /datadoghq/)
```

For VCR provide a list of Datadog backend hosts as ignored hosts:

```ruby
VCR.configure do |config|
  # note to use the correct datadog site (e.g. datadoghq.eu, etc)
  config.ignore_hosts "citestcycle-intake.datadoghq.com", "api.datadoghq.com", "citestcov-intake.datadoghq.com"
end
```
