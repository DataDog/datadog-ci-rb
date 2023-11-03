require "datadog/core/utils/sequence"

require_relative "context"

module Datadog
  module CI
    # Provider is a default context provider that retrieves
    # all contexts from the current fiber-local storage. It is suitable for
    # synchronous programming.
    #
    # @see https://ruby-doc.org/core-3.1.2/Thread.html#method-i-5B-5D Thread attributes are fiber-local
    class ContextProvider
      # Initializes the default context provider with a fiber-bound context.
      def initialize
        @context = FiberLocalContext.new
      end

      # Sets the current context.
      def context=(ctx)
        @context.local = ctx
      end

      # Return the local context.
      def context(key = nil)
        current_context = key.nil? ? @context.local : @context.local(key)

        current_context.after_fork! do
          current_context = self.context = current_context.fork_clone
        end

        current_context
      end
    end

    class FiberLocalContext
      def initialize
        @key = "datadog_ci_context_#{FiberLocalContext.next_instance_id}".to_sym

        self.local = Context.new
      end

      # Override the fiber-local context with a new context.
      def local=(ctx)
        Thread.current[@key] = ctx
      end

      # Return the fiber-local context.
      def local(storage = Thread.current)
        storage[@key] ||= Context.new
      end

      UNIQUE_INSTANCE_MUTEX = Mutex.new
      UNIQUE_INSTANCE_GENERATOR = Datadog::Core::Utils::Sequence.new

      private_constant :UNIQUE_INSTANCE_MUTEX, :UNIQUE_INSTANCE_GENERATOR

      def self.next_instance_id
        UNIQUE_INSTANCE_MUTEX.synchronize { UNIQUE_INSTANCE_GENERATOR.next }
      end
    end
  end
end
