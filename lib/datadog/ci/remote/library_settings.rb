# frozen_string_literal: true

require "json"

require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/telemetry"
require_relative "../utils/parsing"

require_relative "slow_test_retries"

module Datadog
  module CI
    module Remote
      # Wrapper around the settings HTTP response
      class LibrarySettings
        def initialize(http_response)
          @http_response = http_response
          @json = nil
        end

        def ok?
          resp = @http_response
          !resp.nil? && resp.ok?
        end

        def payload
          cached = @json
          return cached unless cached.nil?

          resp = @http_response
          return @json = default_payload if resp.nil? || !ok?

          begin
            @json = JSON.parse(resp.payload).dig(*Ext::Transport::DD_API_SETTINGS_RESPONSE_DIG_KEYS) ||
              default_payload
          rescue JSON::ParserError => e
            Datadog.logger.error("Failed to parse settings response payload: #{e}. Payload was: #{resp.payload}")

            Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_GIT_REQUESTS_SETTINGS_ERRORS,
              1,
              error_type: "invalid_json",
              status_code: nil
            )

            @json = default_payload
          end
        end

        def require_git?
          return @require_git if defined?(@require_git)

          @require_git = Utils::Parsing.convert_to_bool(
            payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_REQUIRE_GIT_KEY, false)
          )
        end

        def itr_enabled?
          return @itr_enabled if defined?(@itr_enabled)

          @itr_enabled = Utils::Parsing.convert_to_bool(
            payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_ITR_ENABLED_KEY, false)
          )
        end

        def code_coverage_enabled?
          return @code_coverage_enabled if defined?(@code_coverage_enabled)

          @code_coverage_enabled = Utils::Parsing.convert_to_bool(
            payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_CODE_COVERAGE_KEY, false)
          )
        end

        def tests_skipping_enabled?
          return @tests_skipping_enabled if defined?(@tests_skipping_enabled)

          @tests_skipping_enabled = Utils::Parsing.convert_to_bool(
            payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_TESTS_SKIPPING_KEY, false)
          )
        end

        def flaky_test_retries_enabled?
          return @flaky_test_retries_enabled if defined?(@flaky_test_retries_enabled)

          @flaky_test_retries_enabled = Utils::Parsing.convert_to_bool(
            payload.fetch(
              Ext::Transport::DD_API_SETTINGS_RESPONSE_FLAKY_TEST_RETRIES_KEY, false
            )
          )
        end

        def early_flake_detection_enabled?
          return @early_flake_detection_enabled if defined?(@early_flake_detection_enabled)

          @early_flake_detection_enabled = Utils::Parsing.convert_to_bool(
            early_flake_detection_payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_ENABLED_KEY, false)
          )
        end

        def known_tests_enabled?
          return @known_tests_enabled if defined?(@known_tests_enabled)

          @known_tests_enabled = Utils::Parsing.convert_to_bool(
            payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_KNOWN_TESTS_ENABLED_KEY, false)
          )
        end

        def slow_test_retries
          return @slow_test_retries if defined?(@slow_test_retries)

          @slow_test_retries = SlowTestRetries.new(
            early_flake_detection_payload.fetch(Ext::Transport::DD_API_SETTINGS_RESPONSE_SLOW_TEST_RETRIES_KEY, {})
          )
        end

        def faulty_session_threshold
          return @faulty_session_threshold if defined?(@faulty_session_threshold)

          @faulty_session_threshold = early_flake_detection_payload.fetch(
            Ext::Transport::DD_API_SETTINGS_RESPONSE_FAULTY_SESSION_THRESHOLD_KEY, 0
          )
        end

        private

        def early_flake_detection_payload
          payload.fetch(
            Ext::Transport::DD_API_SETTINGS_RESPONSE_EARLY_FLAKE_DETECTION_KEY,
            {}
          )
        end

        def default_payload
          Ext::Transport::DD_API_SETTINGS_RESPONSE_DEFAULT
        end
      end
    end
  end
end
