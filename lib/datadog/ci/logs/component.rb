# frozen_string_literal: true

require "datadog/core/environment/platform"

module Datadog
  module CI
    module Logs
      class Component
        attr_reader :enabled

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
          test_session = test_visibility.active_test_session

          event[:ddsource] ||= "ruby"
          event[:ddtags] ||= "datadog.product:citest"
          event[:service] ||= test_session&.service
          event[:hostname] ||= Datadog::Core::Environment::Platform.hostname
        end

        def test_visibility
          ::Datadog.send(:components).test_visibility
        end
      end
    end
  end
end
