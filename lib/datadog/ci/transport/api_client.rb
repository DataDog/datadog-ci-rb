# frozen_string_literal: true

require "datadog/core/environment/identity"

require_relative "../ext/transport"

module Datadog
  module CI
    module Transport
      # Datadog API client
      # Calls settings endpoint to fetch library settings for given service and env
      class ApiClient
        def initialize(api: nil)
          @api = api
        end

        def fetch_library_settings(service:)
          # TODO: return error response if api is not present
          return {} unless @api
          # TODO: id generation
          # TODO: runtime information is required for payload
          # TODO: return error response - use some wrapper from ddtrace as an example
          @api.api_request(
            path: Ext::Transport::DD_API_SETTINGS_PATH,
            payload: settings_payload(service: service)
          )
        end

        private

        def settings_payload(service:)
          {
            data: {
              id: Datadog::Core::Environment::Identity.id,
              type: Ext::Transport::DD_API_SETTINGS_TYPE,
              attributes: {
                service: service
              }
            }
          }.to_json
        end
      end
    end
  end
end
