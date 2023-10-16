# frozen_string_literal: true

module Datadog
  module CI
    module Transport
      module Api
        class Base
          def request(path:, payload:, verb: "post")
          end

          private

          def headers
            @headers ||= {
              Ext::Transport::HEADER_CONTENT_TYPE => Ext::Transport::CONTENT_TYPE_MESSAGEPACK
            }
          end
        end
      end
    end
  end
end
