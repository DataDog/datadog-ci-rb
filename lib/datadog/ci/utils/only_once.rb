# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      class OnlyOnce
        def initialize
          @mutex = Mutex.new
          @ran = false
        end

        def run
          @mutex.synchronize do
            return if @ran
            yield
            @ran = true
          end
        end

        def ran?
          @mutex.synchronize { @ran }
        end

        def reset!
          @mutex.synchronize { @ran = false }
        end
      end
    end
  end
end
