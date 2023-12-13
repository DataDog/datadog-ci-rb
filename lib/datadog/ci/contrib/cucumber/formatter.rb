# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Cucumber
        # Defines collection of instrumented Cucumber events
        class Formatter
          attr_reader :config
          private :config

          def initialize(config)
            @config = config

            bind_events(config)
          end

          def bind_events(config)
            config.on_event :test_run_started, &method(:on_test_run_started)
            config.on_event :test_run_finished, &method(:on_test_run_finished)
            config.on_event :test_case_started, &method(:on_test_case_started)
            config.on_event :test_case_finished, &method(:on_test_case_finished)
            config.on_event :test_step_started, &method(:on_test_step_started)
            config.on_event :test_step_finished, &method(:on_test_step_finished)
          end

          def on_test_run_started(event)
            p "TEST RUN!"
            test_session = CI.start_test_session(
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => Ext::TEST_TYPE
              },
              service: configuration[:service_name]
            )
            CI.start_test_module(test_session.name)
          end

          def on_test_run_finished(event)
            test_session = CI.active_test_session
            test_module = CI.active_test_module

            if test_session && test_module
              if event.respond_to?(:success)
                if event.success
                  test_module.passed!
                  test_session.passed!
                else
                  test_module.failed!
                  test_session.failed!
                end
              else
                # we need to track results manually if we are using cucumber < 8.0
                test_module.passed!
                test_session.passed!
              end
              test_module.finish
              test_session.finish
            end
          end

          def on_test_case_started(event)
            CI.start_test(
              event.test_case.name,
              event.test_case.location.file,
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => Ext::TEST_TYPE
              },
              service: configuration[:service_name]
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
