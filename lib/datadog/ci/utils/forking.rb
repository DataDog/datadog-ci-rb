# frozen_string_literal: true

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
          Process.pid != fork_pid
        end

        def update_fork_pid!
          @fork_pid = Process.pid
        end

        def fork_pid
          @fork_pid ||= Process.pid
        end
      end
    end
  end
end
