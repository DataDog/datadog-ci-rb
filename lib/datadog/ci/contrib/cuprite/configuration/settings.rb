# frozen_string_literal: true

require "datadog/core"

require_relative "../ext"
require_relative "../../settings"

require_relative "../../../ext/rum"

module Datadog
  module CI
    module Contrib
      module Cuprite
        module Configuration
          # Custom settings for the Cuprite integration
          # @public_api
          class Settings < Datadog::CI::Contrib::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            option :rum_flush_wait_millis do |o|
              o.type :int
              o.env CI::Ext::RUM::ENV_RUM_FLUSH_WAIT_MILLIS
              o.default 500
            end
          end
        end
      end
    end
  end
end
