# frozen_string_literal: true

require_relative "../ext/test"
require_relative "../ext/transport"

require_relative "../utils/git"

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

          Datadog.logger.debug("ITR Runner initialized with enabled: #{@enabled}")
        end

        def configure(remote_configuration, test_session)
          Datadog.logger.debug("Configuring ITR Runner with remote configuration: #{remote_configuration}")

          @enabled = convert_to_bool(
            remote_configuration.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_ITR_ENABLED_KEY, false)
          )
          @test_skipping_enabled = @enabled && convert_to_bool(
            remote_configuration.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_TESTS_SKIPPING_KEY, false)
          )
          @code_coverage_enabled = @enabled && convert_to_bool(
            remote_configuration.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_CODE_COVERAGE_KEY, false)
          )

          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_ENABLED, @test_skipping_enabled)
          # currently we set this tag when ITR requires collecting code coverage
          # this will change as soon as we implement total code coverage support in this library
          test_session.set_tag(Ext::Test::TAG_CODE_COVERAGE_ENABLED, @code_coverage_enabled)

          # we skip tests, not suites
          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_TYPE, Ext::Test::ITR_TEST_SKIPPING_MODE)

          load_datadog_cov! if @code_coverage_enabled

          Datadog.logger.debug("Configured ITR Runner with enabled: #{@enabled}, skipping_tests: #{@test_skipping_enabled}, code_coverage: #{@code_coverage_enabled}")
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

        def start_coverage
          return if !enabled? || !code_coverage?

          coverage_collector&.start
        end

        def stop_coverage(_test)
          return if !enabled? || !code_coverage?

          coverage_collector&.stop
        end

        private

        def coverage_collector
          Thread.current[:dd_coverage_collector] ||= Coverage::DDCov.new(root: Utils::Git.root)
        end

        def load_datadog_cov!
          require "datadog_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
        rescue LoadError => e
          Datadog.logger.error("Failed to load coverage collector: #{e}. Code coverage will not be collected.")

          @code_coverage_enabled = false
        end

        def convert_to_bool(value)
          value.to_s == "true"
        end
      end
    end
  end
end
