# frozen_string_literal: true

require "json"

require "datadog/core/environment/identity"

require_relative "../ext/transport"

module Datadog
  module CI
    module Transport
      # Datadog API client
      # Calls settings endpoint to fetch library settings for given service and env
      #
      # TODO: Rename ApiClient to SettingsApiClient
      class ApiClient
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
            return @json if @json

            resp = @http_response
            return default_payload if resp.nil? || !resp.ok?

            begin
              @json = JSON.parse(resp.payload).dig("data", "attributes")
            rescue JSON::ParserError => e
              Datadog.logger.error("Failed to parse settings response payload: #{e}. Payload was: #{resp.payload}")
              @json = default_payload
            end
          end

          private

          def default_payload
            {"itr_enabled" => false}
          end
        end

        def initialize(api: nil, dd_env: nil)
          @api = api
          @dd_env = dd_env
        end

        def fetch_library_settings(test_session)
          api = @api
          return Response.new(nil) unless api

          Response.new(
            api.api_request(
              path: Ext::Transport::DD_API_SETTINGS_PATH,
              payload: payload(test_session)
            )
          )
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
