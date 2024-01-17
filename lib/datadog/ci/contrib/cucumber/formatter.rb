# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../utils/git"
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
            @ast_lookup = ::Cucumber::Formatter::AstLookup.new(config) if defined?(::Cucumber::Formatter::AstLookup)

            @config = config
            @failed_tests_count = 0

            @current_test_suite = nil

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
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s
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
            test_suite_name = test_suite_name(event.test_case)

            tags = {
              CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
              CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Cucumber::Integration.version.to_s,
              CI::Ext::Test::TAG_TYPE => CI::Ext::Test::TEST_TYPE,
              CI::Ext::Test::TAG_SOURCE_FILE => Utils::Git.relative_to_root(event.test_case.location.file),
              CI::Ext::Test::TAG_SOURCE_START => event.test_case.location.line.to_s
            }

            start_test_suite(test_suite_name) unless same_test_suite_as_current?(test_suite_name)

            test_span = CI.start_test(
              event.test_case.name,
              test_suite_name,
              tags: tags,
              service: configuration[:service_name]
            )

            if (parameters = extract_parameters_hash(event.test_case))
              test_span.set_parameters(parameters)
            end
          end

          def on_test_case_finished(event)
            test_span = CI.active_test
            return if test_span.nil?

            # We need to track overall test failures manually if we are using cucumber < 8.0 because
            # TestRunFinished event does not have a success attribute before 8.0.
            #
            if event.result.failed?
              @failed_tests_count += 1

              test_suite = @current_test_suite
              test_suite.failed! if test_suite
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

          def test_suite_name(test_case)
            feature = if test_case.respond_to?(:feature)
              test_case.feature
            elsif @ast_lookup
              gherkin_doc = @ast_lookup.gherkin_document(test_case.location.file)
              gherkin_doc.feature if gherkin_doc
            end

            if feature
              "#{feature.name} at #{test_case.location.file}"
            else
              test_case.location.file
            end
          end

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

            test_suite = CI.start_test_suite(test_suite_name)
            # will be overridden if any test fails
            test_suite.passed!

            @current_test_suite = test_suite
          end

          def finish_current_test_suite
            test_suite = @current_test_suite
            return unless test_suite

            test_suite.finish
          end

          def same_test_suite_as_current?(test_suite_name)
            test_suite = @current_test_suite
            return false unless test_suite

            test_suite.name == test_suite_name
          end

          def extract_parameters_hash(test_case)
            # not supported in cucumber < 4.0
            return nil unless @ast_lookup

            scenario_source = @ast_lookup.scenario_source(test_case)

            # cucumber examples are only supported for scenario outlines
            return nil unless scenario_source.type == :ScenarioOutline

            scenario_source.examples.table_header.cells.map(&:value).zip(
              scenario_source.row.cells.map(&:value)
            ).to_h
          rescue => e
            Datadog.logger.warn do
              "Unable to extract parameters from test case #{test_case.name}: " \
                "#{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
            end

            nil
          end

          def configuration
            Datadog.configuration.ci[:cucumber]
          end
        end
      end
    end
  end
end
