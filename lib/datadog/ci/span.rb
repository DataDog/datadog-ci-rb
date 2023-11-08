# frozen_string_literal: true

require_relative "ext/test"

module Datadog
  module CI
    # Represents a single part of a test run.
    # Could be a session, suite, test, or any custom span.
    #
    # @public_api
    class Span
      attr_reader :tracer_span

      def initialize(tracer_span)
        @tracer_span = tracer_span
      end

      # @return [String] the name of the span.
      def name
        tracer_span.name
      end

      # @return [String] the type of the span (for example "test" or type that was provided to [Datadog::CI.trace]).
      def span_type
        tracer_span.type
      end

      # Sets the status of the span to "pass".
      # @return [void]
      def passed!
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::PASS)
      end

      # Sets the status of the span to "fail".
      # @param [Exception] exception the exception that caused the test to fail.
      # @return [void]
      def failed!(exception: nil)
        tracer_span.status = 1
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::FAIL)
        tracer_span.set_error(exception) unless exception.nil?
      end

      # Sets the status of the span to "skip".
      # @param [Exception] exception the exception that caused the test to fail.
      # @param [String] reason the reason why the test was skipped.
      # @return [void]
      def skipped!(exception: nil, reason: nil)
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::SKIP)
        tracer_span.set_error(exception) unless exception.nil?
        tracer_span.set_tag(Ext::Test::TAG_SKIP_REASON, reason) unless reason.nil?
      end

      # Gets tag value by key.
      # @param [String] key the key of the tag.
      # @return [String] the value of the tag.
      def get_tag(key)
        tracer_span.get_tag(key)
      end

      # Sets tag value by key.
      # @param [String] key the key of the tag.
      # @param [String] value the value of the tag.
      # @return [void]
      def set_tag(key, value)
        tracer_span.set_tag(key, value)
      end

      # Sets metric value by key.
      # @param [String] key the key of the metric.
      # @param [Numeric] value the value of the metric.
      # @return [void]
      def set_metric(key, value)
        tracer_span.set_metric(key, value)
      end

      # Finishes the span.
      # @return [void]
      def finish
        tracer_span.finish
      end

      # Sets multiple tags at once.
      # @param [Hash[String, String]] tags the tags to set.
      # @return [void]
      def set_tags(tags)
        tags.each do |key, value|
          tracer_span.set_tag(key, value)
        end
      end

      def set_environment_runtime_tags
        tracer_span.set_tag(Ext::Test::TAG_OS_ARCHITECTURE, ::RbConfig::CONFIG["host_cpu"])
        tracer_span.set_tag(Ext::Test::TAG_OS_PLATFORM, ::RbConfig::CONFIG["host_os"])
        tracer_span.set_tag(Ext::Test::TAG_RUNTIME_NAME, Core::Environment::Ext::LANG_ENGINE)
        tracer_span.set_tag(Ext::Test::TAG_RUNTIME_VERSION, Core::Environment::Ext::ENGINE_VERSION)
      end

      def set_default_tags
        tracer_span.set_tag(Ext::Test::TAG_SPAN_KIND, Ext::AppTypes::TYPE_TEST)
      end

      def to_s
        "#{self.class}(name:#{name},tracer_span:#{@tracer_span})"
      end
    end
  end
end
