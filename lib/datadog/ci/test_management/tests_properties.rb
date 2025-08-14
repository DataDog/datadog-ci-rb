# frozen_string_literal: true

require "json"

require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/telemetry"
require_relative "../utils/parsing"
require_relative "../utils/telemetry"
require_relative "../utils/test_run"

module Datadog
  module CI
    module TestManagement
      # fetches and stores a map of tests to their test management properties from the backend
      class TestsProperties
        class Response
          def initialize(http_response, json: nil)
            @http_response = http_response
            @json = json
          end

          def ok?
            resp = @http_response
            !resp.nil? && resp.ok?
          end

          def tests
            tests_map = {}

            payload
              .fetch("data", {})
              .fetch("attributes", {})
              .fetch("modules", {})
              .each do |_test_module, module_hash|
                module_hash
                  .fetch("suites", {})
                  .each do |test_suite, suite_hash|
                    suite_hash.fetch("tests", {})
                      .each do |test_name, properties_hash|
                        properties = properties_hash.fetch("properties", {})
                        properties.transform_values! { |v| Utils::Parsing.convert_to_bool(v) }

                        tests_map[Utils::TestRun.datadog_test_id(test_name, test_suite)] = properties
                      end
                  end
              end

            tests_map
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
              Datadog.logger.error(
                "Failed to parse test management tests response payload: #{e}. Payload was: #{resp.payload}"
              )
              @json = {}
            end
          end
        end

        def initialize(api: nil)
          @api = api
        end

        def fetch(test_session)
          api = @api
          return {} unless api

          request_payload = payload(test_session)
          Datadog.logger.debug("Fetching test management tests with request: #{request_payload}")

          http_response = api.api_request(
            path: Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_PATH,
            payload: request_payload
          )

          CI::Transport::Telemetry.api_requests(
            Ext::Telemetry::METRIC_TEST_MANAGEMENT_TESTS_REQUEST,
            1,
            compressed: http_response.request_compressed
          )
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_TEST_MANAGEMENT_TESTS_REQUEST_MS, http_response.duration_ms)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_TEST_MANAGEMENT_TESTS_RESPONSE_BYTES,
            http_response.response_size.to_f,
            {Ext::Telemetry::TAG_RESPONSE_COMPRESSED => http_response.gzipped_content?.to_s}
          )

          unless http_response.ok?
            CI::Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_TEST_MANAGEMENT_TESTS_REQUEST_ERRORS,
              1,
              error_type: http_response.telemetry_error_type,
              status_code: http_response.code
            )
          end

          Response.new(http_response).tests
        end

        private

        def payload(test_session)
          {
            "data" => {
              "id" => Datadog::Core::Environment::Identity.id,
              "type" => Ext::Transport::DD_API_TEST_MANAGEMENT_TESTS_TYPE,
              "attributes" => {
                "repository_url" => test_session.git_repository_url,
                "commit_message" => test_session.original_git_commit_message,
                "sha" => test_session.original_git_commit_sha
              }
            }
          }.to_json
        end
      end
    end
  end
end
