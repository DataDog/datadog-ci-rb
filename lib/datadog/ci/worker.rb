# frozen_string_literal: true

require "datadog/core/worker"
require "datadog/core/workers/async"

# general purpose async worker for CI
# executes given task once in separate thread
module Datadog
  module CI
    class Worker < Datadog::Core::Worker
      include Datadog::Core::Workers::Async::Thread

      DEFAULT_SHUTDOWN_TIMEOUT = 60

      def stop(timeout = DEFAULT_SHUTDOWN_TIMEOUT)
        join(timeout)
      end

      def wait_until_done(timeout = nil)
        join(timeout)
      end

      def done?
        started? && !running?
      end
    end

    class DummyWorker < Worker
      def initialize
        super { nil }
      end
    end
  end
end
