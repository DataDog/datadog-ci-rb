# frozen_string_literal: true

require_relative "base"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # TODO
          class Default < Base
            def tags
              {}
            end
          end
        end
      end
    end
  end
end
