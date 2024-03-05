# frozen_string_literal: true

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
        def initialize(api: nil, dd_env: nil)
          @api = api
          @dd_env = dd_env
        end

        def fetch_library_settings(test_session)
          # TODO: return error response if api is not present
          api = @api
          return {} unless api
          # TODO: return error response - use some wrapper from ddtrace as an example
          api.api_request(
            path: Ext::Transport::DD_API_SETTINGS_PATH,
            payload: payload(test_session)
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
