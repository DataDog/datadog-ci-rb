# frozen_string_literal: true

require "json"

require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/telemetry"
require_relative "../utils/telemetry"
require_relative "../utils/test_run"

module Datadog
  module CI
    module TestRetries
      # fetch a list of unique known tests from the backend
      class UniqueTestsClient
        class Response
          def initialize(http_response)
            @http_response = http_response
            @json = nil
          end

          def ok?
            resp = @http_response
            !resp.nil? && resp.ok?
          end

          def tests
            res = Set.new

            payload
              .fetch("data", {})
              .fetch("attributes", {})
              .fetch("tests", {})
              .each do |_test_module, suites_hash|
                suites_hash.each do |test_suite, tests|
                  tests.each do |test_name|
                    res << Utils::TestRun.datadog_test_id(test_name, test_suite)
                  end
                end
              end

            res
          end

          private

          def payload
            cached = @json
            return cached unless cached.nil?

            resp = @http_response
            return @json = {} if resp.nil? || !ok?

            begin
              @json = JSON.parse(resp.payload)
            rescue JSON::ParserError => e
              Datadog.logger.error("Failed to parse unique known tests response payload: #{e}. Payload was: #{resp.payload}")
              @json = {}
            end
          end
        end

        def initialize(dd_env:, api: nil, config_tags: {})
          @api = api
          @dd_env = dd_env
          @config_tags = config_tags
        end

        def fetch_unique_tests(test_session)
          api = @api
          return Response.new(nil) unless api

          request_payload = payload(test_session)
          Datadog.logger.debug("Fetching unique known tests with request: #{request_payload}")

          http_response = api.api_request(
            path: Ext::Transport::DD_API_UNIQUE_TESTS_PATH,
            payload: request_payload
          )

          Transport::Telemetry.api_requests(
            Ext::Telemetry::METRIC_EFD_UNIQUE_TESTS_REQUEST,
            1,
            compressed: http_response.request_compressed
          )
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_EFD_UNIQUE_TESTS_REQUEST_MS, http_response.duration_ms)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_EFD_UNIQUE_TESTS_RESPONSE_BYTES,
            http_response.response_size.to_f,
            {Ext::Telemetry::TAG_RESPONSE_COMPRESSED => http_response.gzipped_content?.to_s}
          )

          unless http_response.ok?
            Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_EFD_UNIQUE_TESTS_REQUEST_ERRORS,
              1,
              error_type: http_response.telemetry_error_type,
              status_code: http_response.code
            )
          end

          Response.new(http_response)
        end

        private

        def payload(test_session)
          {
            "data" => {
              "id" => Datadog::Core::Environment::Identity.id,
              "type" => Ext::Transport::DD_API_UNIQUE_TESTS_TYPE,
              "attributes" => {
                "repository_url" => test_session.git_repository_url,
                "service" => test_session.service,
                "env" => @dd_env,
                "sha" => test_session.git_commit_sha,
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
