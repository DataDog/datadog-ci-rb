# frozen_string_literal: true

require "json"

require_relative "../ext/transport"
require_relative "../ext/test"
require_relative "../utils/test_run"

module Datadog
  module CI
    module ITR
      class Skippable
        class Response
          def initialize(http_response)
            @http_response = http_response
            @json = nil
          end

          def ok?
            resp = @http_response
            !resp.nil? && resp.ok?
          end

          def correlation_id
            payload.dig("meta", "correlation_id")
          end

          def tests
            res = Set.new

            payload.fetch("data", [])
              .each do |test_data|
                next unless test_data["type"] == Ext::Test::ITR_TEST_SKIPPING_MODE

                attrs = test_data["attributes"] || {}
                res << Utils::TestRun.skippable_test_id(attrs["name"], attrs["suite"], attrs["parameters"])
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
              Datadog.logger.error("Failed to parse skippable tests response payload: #{e}. Payload was: #{resp.payload}")
              @json = {}
            end
          end
        end

        def initialize(dd_env:, api: nil, config_tags: {})
          @api = api
          @dd_env = dd_env
          @config_tags = config_tags
        end

        def fetch_skippable_tests(test_session)
          api = @api
          return Response.new(nil) unless api

          request_payload = payload(test_session)
          Datadog.logger.debug("Fetching skippable tests with request: #{request_payload}")

          http_response = api.api_request(
            path: Ext::Transport::DD_API_SKIPPABLE_TESTS_PATH,
            payload: request_payload
          )

          Response.new(http_response)
        end

        private

        def payload(test_session)
          {
            "data" => {
              "type" => Ext::Transport::DD_API_SKIPPABLE_TESTS_TYPE,
              "attributes" => {
                "test_level" => Ext::Test::ITR_TEST_SKIPPING_MODE,
                "service" => test_session.service,
                "env" => @dd_env,
                "repository_url" => test_session.git_repository_url,
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
