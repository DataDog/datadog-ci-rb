# frozen_string_literal: true

require_relative "identity"

module Datadog
  module CI
    module Utils
      module Forking
        def after_fork!
          return false unless forked?

          yield
          update_fork_pid!
          true
        end

        def forked?
          Utils::Identity.pid != fork_pid
        end

        def update_fork_pid!
          @fork_pid = Utils::Identity.pid
        end

        def fork_pid
          @fork_pid ||= Utils::Identity.pid
        end
      end
    end
  end
end
