# frozen_string_literal: true

require "json"

require_relative "../ext/transport"
require_relative "../ext/test"

module Datadog
  module CI
    module ITR
      class Skippable
        class Test
          attr_reader :name, :suite

          def initialize(name:, suite:)
            @name = name
            @suite = suite
          end

          def ==(other)
            name == other.name && suite == other.suite
          end
        end

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
            payload.fetch("data", [])
              .filter_map do |test_data|
                next unless test_data["type"] == Ext::Test::ITR_TEST_SKIPPING_MODE

                attrs = test_data["attributes"] || {}
                Test.new(name: attrs["name"], suite: attrs["suite"])
              end
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

        def initialize(api: nil, dd_env: nil)
          @api = api
          @dd_env = dd_env
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
                  "os.platform" => test_session.os_platform,
                  "os.architecture" => test_session.os_architecture,
                  "runtime.name" => test_session.runtime_name,
                  "runtime.version" => test_session.runtime_version
                }
              }
            }
          }.to_json
        end
      end
    end
  end
end
