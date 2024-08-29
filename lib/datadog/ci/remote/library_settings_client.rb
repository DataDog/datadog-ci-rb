# frozen_string_literal: true

require "json"

require "datadog/core/environment/identity"

require_relative "library_settings"

require_relative "../ext/test"
require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module Remote
      # Calls settings endpoint to fetch library settings for given service and env
      class LibrarySettingsClient
        def initialize(dd_env:, api: nil, config_tags: {})
          @api = api
          @dd_env = dd_env
          @config_tags = config_tags || {}
        end

        def fetch(test_session)
          api = @api
          return LibrarySettings.new(nil) unless api

          request_payload = payload(test_session)
          Datadog.logger.debug("Fetching library settings with request: #{request_payload}")

          http_response = api.api_request(
            path: Ext::Transport::DD_API_SETTINGS_PATH,
            payload: request_payload
          )

          Transport::Telemetry.api_requests(
            Ext::Telemetry::METRIC_GIT_REQUESTS_SETTINGS,
            1,
            compressed: http_response.request_compressed
          )
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_GIT_REQUESTS_SETTINGS_MS, http_response.duration_ms)

          unless http_response.ok?
            Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_GIT_REQUESTS_SETTINGS_ERRORS,
              1,
              error_type: http_response.telemetry_error_type,
              status_code: http_response.code
            )
          end

          library_settings = LibrarySettings.new(http_response)

          Utils::Telemetry.inc(
            Ext::Telemetry::METRIC_GIT_REQUESTS_SETTINGS_RESPONSE,
            1,
            {
              Ext::Telemetry::TAG_COVERAGE_ENABLED => library_settings.code_coverage_enabled?.to_s,
              Ext::Telemetry::TAG_ITR_SKIP_ENABLED => library_settings.tests_skipping_enabled?.to_s,
              Ext::Telemetry::TAG_EARLY_FLAKE_DETECTION_ENABLED => library_settings.early_flake_detection_enabled?.to_s
            }
          )

          library_settings
        end

        private

        def payload(test_session)
          {
            "data" => {
              "id" => Datadog::Core::Environment::Identity.id,
              "type" => Ext::Transport::DD_API_SETTINGS_TYPE,
              "attributes" => {
                "service" => test_session.service,
                "env" => @dd_env,
                "repository_url" => test_session.git_repository_url,
                "branch" => test_session.git_branch,
                "sha" => test_session.git_commit_sha,
                "test_level" => Ext::Test::ITR_TEST_SKIPPING_MODE,
                "configurations" => {
                  Ext::Test::TAG_OS_PLATFORM => test_session.os_platform,
                  Ext::Test::TAG_OS_ARCHITECTURE => test_session.os_architecture,
                  Ext::Test::TAG_OS_VERSION => test_session.os_version,
                  Ext::Test::TAG_RUNTIME_NAME => test_session.runtime_name,
                  Ext::Test::TAG_RUNTIME_VERSION => test_session.runtime_version,
                  "custom" => @config_tags
                }
              }
            }
          }.to_json
        end
      end
    end
  end
end
