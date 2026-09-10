# frozen_string_literal: true

require "datadog/core/environment/platform"

require_relative "../async_writer"
require_relative "transport"

module Datadog
  module CI
    module Logs
      class Component
        attr_reader :enabled

        def self.build(enabled:, api:, discard_traces:)
          writer = unless api.nil? || discard_traces
            AsyncWriter.new(transport: Transport.new(api: api), options: {buffer_size: 1024})
          end

          new(enabled: enabled, writer: writer)
        end

        def initialize(enabled:, writer:)
          @enabled = enabled && !writer.nil?
          @writer = writer
        end

        def write(event)
          return unless enabled

          add_common_tags!(event)
          @writer&.write(event)

          nil
        end

        def shutdown!
          @writer&.stop
        end

        private

        def add_common_tags!(event)
          test_session = test_tracing.active_test_session

          event[:ddsource] ||= "ruby"
          event[:ddtags] ||= "datadog.product:citest"
          event[:service] ||= test_session&.service
          event[:hostname] ||= Datadog::Core::Environment::Platform.hostname
        end

        def test_tracing
          ::Datadog.send(:components).test_tracing
        end
      end
    end
  end
end
