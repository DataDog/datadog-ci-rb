# frozen_string_literal: true

# +SimpleCov.start+ must be invoked before any application code is loaded
require "simplecov"
SimpleCov.start do
  formatter SimpleCov::Formatter::SimpleFormatter
end

require_relative "../lib/datadog/ci"

# rspec helpers and matchers
require_relative "support/gems_helpers"

require_relative "support/tracer_helpers"
require_relative "support/span_helpers"
require_relative "support/provider_test_helpers"
require_relative "support/test_visibility_event_serialized"

# shared contexts
require_relative "support/contexts/ci_mode"
require_relative "support/contexts/concurrency_test"
require_relative "support/contexts/git_fixture"

require "rspec/collection_matchers"
require "climate_control"
require "timecop"

if defined?(Warning.ignore)
  # Caused by https://github.com/cucumber/cucumber-ruby/blob/47c8e2d7c97beae8541c895a43f9ccb96324f0f1/lib/cucumber/encoding.rb#L5-L6
  Gem.path.each do |path|
    Warning.ignore(/setting Encoding.default_external/, path)
    Warning.ignore(/setting Encoding.default_internal/, path)
  end
end

require "rubygems" unless defined? Gem

# Caused by https://github.com/simplecov-ruby/simplecov/pull/756 - simplecov plugin for minitest breaks
# code coverage when running minitest tests under rspec suite.
if Gem.loaded_specs.has_key?("minitest")
  require "minitest"
  module Minitest
    def self.load_plugins
      return unless extensions.empty?
      seen = {}
      Gem.find_files("minitest/*_plugin.rb").each do |plugin_path|
        # here is the hack to fix minitest coverage
        next if plugin_path.include?("simplecov")

        name = File.basename plugin_path, "_plugin.rb"

        next if seen[name]
        seen[name] = true

        require plugin_path
        extensions << name
      end
    end
  end
end

RSpec.configure do |config|
  config.include TracerHelpers
  config.include SpanHelpers

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Raise error when patching an integration fails.
  # This can be disabled by unstubbing +CommonMethods#on_patch_error+
  require "datadog/tracing/contrib/patcher"
  config.before do
    allow_any_instance_of(Datadog::Tracing::Contrib::Patcher::CommonMethods).to(receive(:on_patch_error)) { |_, e| raise e }
  end

  # Ensure tracer environment is clean before running tests.
  #
  # This is done :before and not :after because doing so after
  # can create noise for test assertions. For example:
  # +expect(Datadog).to receive(:shutdown!).once+
  config.before do
    Datadog.shutdown!
    # without_warnings { Datadog.configuration.reset! }
    Datadog.configuration.reset!
  end
end
