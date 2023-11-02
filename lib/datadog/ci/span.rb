# frozen_string_literal: true

require_relative "ext/test"

module Datadog
  # Public API for Datadog CI visibility
  module CI
    class Span
      attr_reader :tracer_span

      def initialize(tracer_span, tags = nil)
        @tracer_span = tracer_span

        set_tags!(tags) unless tags.nil?
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
        tracer_span.set_tag(CI::Ext::Test::TAG_SKIP_REASON, reason) unless reason.nil?
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

      private

      def set_tags!(tags)
        # set default tags
        tracer_span.set_tag(Ext::Test::TAG_SPAN_KIND, Ext::AppTypes::TYPE_TEST)

        tags.each do |key, value|
          tracer_span.set_tag(key, value)
        end

        set_environment_runtime_tags!
      end

      def set_environment_runtime_tags!
        tracer_span.set_tag(Ext::Test::TAG_OS_ARCHITECTURE, ::RbConfig::CONFIG["host_cpu"])
        tracer_span.set_tag(Ext::Test::TAG_OS_PLATFORM, ::RbConfig::CONFIG["host_os"])
        tracer_span.set_tag(Ext::Test::TAG_RUNTIME_NAME, Core::Environment::Ext::LANG_ENGINE)
        tracer_span.set_tag(Ext::Test::TAG_RUNTIME_VERSION, Core::Environment::Ext::ENGINE_VERSION)
      end
    end
  end
end
