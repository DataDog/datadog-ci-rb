# frozen_string_literal: true

require_relative "client"

module Datadog
  module CI
    module ITR
      # Intelligent test runner implementation
      # Integrates with backend to provide test impact analysis data and
      # skip tests that are not impacted by the changes
      class Runner
        def initialize(
          enabled: false,
          api: nil
        )
          @enabled = enabled
          return unless enabled

          @client = Client.new(api: api)
        end

        def enabled?
          @enabled
        end

        def configure(service:)
          return unless enabled?

          # TODO: error handling when request failed
          # TODO: need to pass runtime information
          @client.fetch_settings(service: service)
        end
      end
    end
  end
end
