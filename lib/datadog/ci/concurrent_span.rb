# frozen_string_literal: true

require_relative "span"

module Datadog
  module CI
    # Represents a single part of a test run that can be safely shared between threads.
    # Examples of shared objects are: TestSession, TestModule, TestSpan.
    #
    # @public_api
    class ConcurrentSpan < Span
      def initialize(tracer_span)
        super

        @mutex = Mutex.new
      end

      # Gets tag value by key. This method is thread-safe.
      # @param [String] key the key of the tag.
      # @return [String] the value of the tag.
      def get_tag(key)
        synchronize { super }
      end

      # Sets tag value by key. This method is thread-safe.
      # @param [String] key the key of the tag.
      # @param [String] value the value of the tag.
      # @return [void]
      def set_tag(key, value)
        synchronize { super }
      end

      # Sets metric value by key. This method is thread-safe.
      # @param [String] key the key of the metric.
      # @param [Numeric] value the value of the metric.
      # @return [void]
      def set_metric(key, value)
        synchronize { super }
      end

      # Finishes the span. This method is thread-safe.
      # @return [void]
      def finish
        synchronize { super }
      end

      # Sets multiple tags at once. This method is thread-safe.
      # @param [Hash[String, String]] tags the tags to set.
      # @return [void]
      def set_tags(tags)
        synchronize { super }
      end

      def synchronize
        @mutex.synchronize { yield }
      end
    end
  end
end
