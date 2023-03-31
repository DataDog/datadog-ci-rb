require "pry"
require "datadog/ci"

Datadog.configure do |c|
  c.service = "datadog-ci-integration-app"
  c.env = "local"

  c.tracing.enabled = true
  c.tracing.test_mode.enabled = true

  c.ci.enabled = true
  c.ci.instrument :rspec
end
