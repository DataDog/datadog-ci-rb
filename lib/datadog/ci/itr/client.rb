# frozen_string_literal: true

require_relative "../ext/itr"

module Datadog
  module CI
    module ITR
      # ITR API client
      # communicates with the CI visibility backend
      class Client
        def initialize(api: nil)
          raise ArgumentError, "Test visibility API is required" unless api

          @api = api
        end

        def fetch_settings(service:)
          # TODO: application/json support
          # TODO: runtime information is required for payload
          # TODO: return error response - use some wrapper from ddtrace as an example
          @api.request(
            path: "/api/v2/ci/libraries/tests/services/setting",
            payload: settings_payload(service: service)
          )
        end

        private

        def settings_payload(service:)
          {
            data: {
              id: "change_me",
              type: Ext::ITR::API_TYPE_SETTINGS,
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
