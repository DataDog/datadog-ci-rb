# Upgrading from ddtrace 1.x to datadog-ci

Test visibility for Ruby is no longer part of `datadog` gem and fully migrated to
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

We work on adding new features to the test visibility product in Ruby (intelligent test runner, git metadata upload, code coverage support) that require new endpoints being allowlisted by WebMock/VCR tools when using agentless mode.

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
