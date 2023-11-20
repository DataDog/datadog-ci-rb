# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Defines collection of instrumented Cucumber events
        class Formatter
          attr_reader :config, :current_feature_span, :current_step_span
          private :config
          private :current_feature_span, :current_step_span

          def initialize(config)
            @config = config

            bind_events(config)
          end

          def bind_events(config)
            config.on_event :test_case_started, &method(:on_test_case_started)
            config.on_event :test_case_finished, &method(:on_test_case_finished)
            config.on_event :test_step_started, &method(:on_test_step_started)
            config.on_event :test_step_finished, &method(:on_test_step_finished)
          end

          def on_test_case_started(event)
            CI.start_test(
              event.test_case.name,
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => Ext::TEST_TYPE,
                CI::Ext::Test::TAG_SUITE => event.test_case.location.file
              },
              service_name: configuration[:service_name],
              operation_name: configuration[:operation_name]
            )
          end

          def on_test_case_finished(event)
            test_span = CI.active_test
            return if test_span.nil?

            if event.result.skipped?
              test_span.skipped!
            elsif event.result.ok?
              test_span.passed!
            elsif event.result.failed?
              test_span.failed!
            end

            test_span.finish
          end

          def on_test_step_started(event)
            CI.trace(Ext::STEP_SPAN_TYPE, event.test_step.to_s)
          end

          def on_test_step_finished(event)
            current_step_span = CI.active_span(Ext::STEP_SPAN_TYPE)
            return if current_step_span.nil?

            if event.result.skipped?
              current_step_span.skipped!
            elsif event.result.ok?
              current_step_span.passed!
            elsif event.result.failed?
              current_step_span.failed!(exception: event.result.exception)
            end

            current_step_span.finish
          end

          private

          def configuration
            Datadog.configuration.ci[:cucumber]
          end
        end
      end
    end
  end
end
