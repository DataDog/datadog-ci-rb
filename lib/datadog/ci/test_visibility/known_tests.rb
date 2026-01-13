# frozen_string_literal: true

require "json"

require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/telemetry"
require_relative "../utils/telemetry"
require_relative "../utils/test_run"

module Datadog
  module CI
    module TestVisibility
      # fetches and stores a list of known tests from the backend
      class KnownTests
        DEFAULT_PAGE_SIZE = 2000

        class Response
          def self.from_http_response(http_response)
            new(http_response, nil)
          end

          def self.from_json(json)
            new(nil, json)
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

          def cursor
            page_info.fetch("cursor", nil)
          end

          def has_next?
            page_info.fetch("has_next", false)
          end

          private

          def initialize(http_response, json)
            @http_response = http_response
            @json = json
          end

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

          def page_info
            payload
              .fetch("data", {})
              .fetch("attributes", {})
              .fetch("page_info", {})
          end
        end

        def initialize(dd_env:, api: nil, config_tags: {})
          @api = api
          @dd_env = dd_env
          @config_tags = config_tags
        end

        def fetch(test_session)
          api = @api
          return Set.new unless api

          result = Set.new
          page_state = nil
          page_number = 1

          loop do
            Datadog.logger.debug { "Fetching known tests page ##{page_number}#{" with cursor" if page_state}" }

            response = fetch_page(api, test_session, page_state: page_state)

            if response.nil?
              Datadog.logger.debug { "Stopping known tests fetch: request for page ##{page_number} failed" }
              break
            end

            page_tests = response.tests
            result.merge(page_tests)
            Datadog.logger.debug { "Received #{page_tests.size} known tests from page ##{page_number} (total so far: #{result.size})" }

            unless response.has_next?
              Datadog.logger.debug { "Stopping known tests fetch: no more pages after page ##{page_number}" }
              break
            end

            page_state = response.cursor
            page_number += 1
          end

          Datadog.logger.debug { "Finished fetching known tests: #{result.size} tests total from #{page_number} page(s)" }
          result
        end

        private

        def fetch_page(api, test_session, page_state: nil)
          request_payload = payload(test_session, page_state: page_state)
          Datadog.logger.debug { "Known tests request payload: #{request_payload}" }

          http_response = api.api_request(
            path: Ext::Transport::DD_API_UNIQUE_TESTS_PATH,
            payload: request_payload
          )

          CI::Transport::Telemetry.api_requests(
            Ext::Telemetry::METRIC_KNOWN_TESTS_REQUEST,
            1,
            compressed: http_response.request_compressed
          )
          Utils::Telemetry.distribution(Ext::Telemetry::METRIC_KNOWN_TESTS_REQUEST_MS, http_response.duration_ms)
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_KNOWN_TESTS_RESPONSE_BYTES,
            http_response.response_size.to_f,
            {Ext::Telemetry::TAG_RESPONSE_COMPRESSED => http_response.gzipped_content?.to_s}
          )

          unless http_response.ok?
            CI::Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_KNOWN_TESTS_REQUEST_ERRORS,
              1,
              error_type: http_response.telemetry_error_type,
              status_code: http_response.code
            )
            return nil
          end

          Response.from_http_response(http_response)
        end

        def payload(test_session, page_state: nil)
          page_info = page_state ? {"page_size" => DEFAULT_PAGE_SIZE, "page_state" => page_state} : {"page_size" => DEFAULT_PAGE_SIZE}

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
                },
                "page_info" => page_info
              }
            }
          }.to_json
        end
      end
    end
  end
end
