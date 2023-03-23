# frozen_string_literal: true

require "ddtrace"
require "datadog/ci"

require "rspec/collection_matchers"

require "support/configuration_helpers"
require "support/log_helpers"
require "support/tracer_helpers"
require "support/span_helpers"
require "support/test_helpers"
require "support/platform_helpers"

require "climate_control"

RSpec.configure do |config|
  config.include ConfigurationHelpers
  config.include TracerHelpers
  config.include SpanHelpers

  config.include TestHelpers::RSpec::Integration, :integration

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
