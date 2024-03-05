# frozen_string_literal: true

require_relative "../ext/transport"

module Datadog
  module CI
    module ITR
      # Intelligent test runner implementation
      # Integrates with backend to provide test impact analysis data and
      # skip tests that are not impacted by the changes
      class Runner
        def initialize(
          enabled: false
        )
          @enabled = enabled
          @test_skipping_enabled = false
          @code_coverage_enabled = false
        end

        def configure(remote_configuration)
          @enabled = convert_to_bool(
            remote_configuration.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_ITR_ENABLED_KEY, false)
          )
          @test_skipping_enabled = @enabled && convert_to_bool(
            remote_configuration.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_TESTS_SKIPPING_KEY, false)
          )
          @code_coverage_enabled = @enabled && convert_to_bool(
            remote_configuration.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_CODE_COVERAGE_KEY, false)
          )
        end

        def enabled?
          @enabled
        end

        def skipping_tests?
          @test_skipping_enabled
        end

        def code_coverage?
          @code_coverage_enabled
        end

        private

        def convert_to_bool(value)
          value.to_s == "true"
        end
      end
    end
  end
end
