# frozen_string_literal: true

require "json"

require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/telemetry"
require_relative "../utils/parsing"

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

          @require_git = bool(Ext::Transport::DD_API_SETTINGS_RESPONSE_REQUIRE_GIT_KEY)
        end

        def itr_enabled?
          return @itr_enabled if defined?(@itr_enabled)

          @itr_enabled = bool(Ext::Transport::DD_API_SETTINGS_RESPONSE_ITR_ENABLED_KEY)
        end

        def code_coverage_enabled?
          return @code_coverage_enabled if defined?(@code_coverage_enabled)

          @code_coverage_enabled = bool(Ext::Transport::DD_API_SETTINGS_RESPONSE_CODE_COVERAGE_KEY)
        end

        def tests_skipping_enabled?
          return @tests_skipping_enabled if defined?(@tests_skipping_enabled)

          @tests_skipping_enabled = bool(Ext::Transport::DD_API_SETTINGS_RESPONSE_TESTS_SKIPPING_KEY)
        end

        def flaky_test_retries_enabled?
          return @flaky_test_retries_enabled if defined?(@flaky_test_retries_enabled)

          @flaky_test_retries_enabled = bool(Ext::Transport::DD_API_SETTINGS_RESPONSE_FLAKY_TEST_RETRIES_KEY)
        end

        private

        def bool(key)
          Utils::Parsing.convert_to_bool(payload.fetch(key, false))
        end

        def default_payload
          Ext::Transport::DD_API_SETTINGS_RESPONSE_DEFAULT
        end
      end
    end
  end
end
