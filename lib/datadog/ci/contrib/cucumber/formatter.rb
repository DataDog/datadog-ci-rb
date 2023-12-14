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
            @failed_tests_count = 0

            @current_test_suite = nil
            @failed_tests_per_test_suite = Hash.new(0)

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
            test_session = CI.start_test_session(
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => CI::Ext::Test::TEST_TYPE
              },
              service: configuration[:service_name]
            )
            CI.start_test_module(test_session.name)
          end

          def on_test_run_finished(event)
            if event.respond_to?(:success)
              finish_session(event.success)
            else
              finish_session(@failed_tests_count.zero?)
            end
          end

          def on_test_case_started(event)
            test_suite_name = event.test_case.location.file

            start_test_suite(test_suite_name) unless same_test_suite_as_current?(test_suite_name)

            CI.start_test(
              event.test_case.name,
              test_suite_name,
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s,
                CI::Ext::Test::TAG_TYPE => CI::Ext::Test::TEST_TYPE
              },
              service: configuration[:service_name]
            )
          end

          def on_test_case_finished(event)
            test_span = CI.active_test
            return if test_span.nil?

            # We need to track overall test failures manually if we are using cucumber < 8.0 because
            # TestRunFinished event does not have a success attribute before 8.0.
            #
            # To track whether test suite failed or passed we need to
            # track the number of failed tests per test suite.
            if event.result.failed?
              @failed_tests_count += 1
              test_suite = @current_test_suite
              @failed_tests_per_test_suite[test_suite.name] += 1 if test_suite
            end

            finish_test(test_span, event.result)
          end

          def on_test_step_started(event)
            CI.trace(Ext::STEP_SPAN_TYPE, event.test_step.to_s)
          end

          def on_test_step_finished(event)
            current_step_span = CI.active_span(Ext::STEP_SPAN_TYPE)
            return if current_step_span.nil?

            finish_test(current_step_span, event.result)
          end

          private

          def finish_test(span, result)
            if result.skipped?
              span.skipped!
            elsif result.ok?
              span.passed!
            elsif result.failed?
              span.failed!(exception: result.exception)
            end
            span.finish
          end

          def finish_session(result)
            finish_current_test_suite

            test_session = CI.active_test_session
            test_module = CI.active_test_module

            return unless test_session && test_module

            if result
              test_module.passed!
              test_session.passed!
            else
              test_module.failed!
              test_session.failed!
            end

            test_module.finish
            test_session.finish
          end

          def start_test_suite(test_suite_name)
            finish_current_test_suite

            @current_test_suite = CI.start_test_suite(test_suite_name)
          end

          def finish_current_test_suite
            test_suite = @current_test_suite
            return unless test_suite

            if @failed_tests_per_test_suite[test_suite.name].zero?
              test_suite.passed!
            else
              test_suite.failed!
            end
            test_suite.finish
          end

          def same_test_suite_as_current?(test_suite_name)
            test_suite = @current_test_suite
            return false unless test_suite

            test_suite.name == test_suite_name
          end

          def configuration
            Datadog.configuration.ci[:cucumber]
          end
        end
      end
    end
  end
end
