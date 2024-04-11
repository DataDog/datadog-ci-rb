# frozen_string_literal: true

require "json"

require "datadog/core/environment/identity"

require_relative "../ext/transport"
require_relative "../utils/parsing"

module Datadog
  module CI
    module Transport
      # Datadog API client
      # Calls settings endpoint to fetch library settings for given service and env
      class RemoteSettingsApi
        class Response
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
            return @json = default_payload if resp.nil? || !resp.ok?

            begin
              @json = JSON.parse(resp.payload).dig(*Ext::Transport::DD_API_SETTINGS_RESPONSE_DIG_KEYS) ||
                default_payload
            rescue JSON::ParserError => e
              Datadog.logger.error("Failed to parse settings response payload: #{e}. Payload was: #{resp.payload}")
              @json = default_payload
            end
          end

          def require_git?
            Utils::Parsing.convert_to_bool(payload[Ext::Transport::DD_API_SETTINGS_RESPONSE_REQUIRE_GIT_KEY])
          end

          private

          def default_payload
            Ext::Transport::DD_API_SETTINGS_RESPONSE_DEFAULT
          end
        end

        def initialize(api: nil, dd_env: nil)
          @api = api
          @dd_env = dd_env
        end

        def fetch_library_settings(test_session)
          api = @api
          return Response.new(nil) unless api

          request_payload = payload(test_session)
          Datadog.logger.debug("Fetching library settings with request: #{request_payload}")

          http_response = api.api_request(
            path: Ext::Transport::DD_API_SETTINGS_PATH,
            payload: request_payload
          )

          Response.new(http_response)
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
                  "os.platform" => test_session.os_platform,
                  "os.arch" => test_session.os_architecture,
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
