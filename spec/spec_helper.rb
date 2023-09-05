# frozen_string_literal: true

# +SimpleCov.start+ must be invoked before any application code is loaded
require "simplecov"
SimpleCov.start do
  formatter SimpleCov::Formatter::SimpleFormatter
end

require_relative "../lib/datadog/ci"

require_relative "support/configuration_helpers"
require_relative "support/log_helpers"
require_relative "support/tracer_helpers"
require_relative "support/span_helpers"
require_relative "support/test_helpers"
require_relative "support/platform_helpers"

require "rspec/collection_matchers"
require "climate_control"

if RUBY_PLATFORM != "java"
  require "debug"
end

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
