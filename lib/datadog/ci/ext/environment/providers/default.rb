# frozen_string_literal: true

require_relative "../extractor"

module Datadog
  module CI
    module Ext
      module Environment
        module Providers
          # TODO
          class Default < Extractor
            def tags
              {}
            end
          end
        end
      end
    end
  end
end
