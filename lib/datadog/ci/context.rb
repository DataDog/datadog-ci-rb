# frozen_string_literal: true

require "datadog/core/utils/forking"

module Datadog
  module CI
    class Context
      include Core::Utils::Forking

      attr_reader \
        :active_test

      def initialize(test: nil)
        @active_test = test
      end

      # Creates a copy of the context, when forked.
      def fork_clone
        # forked_session = @active_session && @active_session.fork_clone
        # do not preserves the active test across forks
        self.class.new
      end
    end
  end
end
