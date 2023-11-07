# frozen_string_literal: true

require_relative "ext/test"

module Datadog
  # Public API for Datadog CI visibility
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

      def name
        tracer_span.name
      end

      def passed!
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::PASS)
      end

      def failed!(exception: nil)
        tracer_span.status = 1
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::FAIL)
        tracer_span.set_error(exception) unless exception.nil?
      end

      def skipped!(exception: nil, reason: nil)
        tracer_span.set_tag(Ext::Test::TAG_STATUS, Ext::Test::Status::SKIP)
        tracer_span.set_error(exception) unless exception.nil?
        tracer_span.set_tag(Ext::Test::TAG_SKIP_REASON, reason) unless reason.nil?
      end

      def get_tag(key)
        tracer_span.get_tag(key)
      end

      def set_tag(key, value)
        tracer_span.set_tag(key, value)
      end

      def set_metric(key, value)
        tracer_span.set_metric(key, value)
      end

      def finish
        tracer_span.finish
      end

      def span_type
        tracer_span.type
      end

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
