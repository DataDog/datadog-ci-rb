# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../../utils/test_run"
require_relative "../instrumentation"
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

            @current_test_suite = nil

            @failed_test_suites_count = 0

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
            test_visibility_component.start_test_session(
              tags: {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
              },
              service: datadog_configuration[:service_name]
            )
            test_visibility_component.start_test_module(Ext::FRAMEWORK)
          end

          def on_test_run_finished(event)
            finish_current_test_suite

            if event.respond_to?(:success)
              finish_session(event.success)
            else
              finish_session(@failed_test_suites_count.zero?)
            end
          end

          def on_test_case_started(event)
            test_suite_name = test_suite_name(event.test_case)

            # @type var tags: Hash[String, String]
            tags = {
              CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
              CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s,
              CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(event.test_case.location.file),
              CI::Ext::Test::TAG_SOURCE_START => event.test_case.location.line.to_s
            }

            if (parameters = extract_parameters_hash(event.test_case))
              tags[CI::Ext::Test::TAG_PARAMETERS] = Utils::TestRun.test_parameters(arguments: parameters)
            end

            unless same_test_suite_as_current?(test_suite_name)
              start_test_suite(
                test_suite_name,
                tags: test_suite_source_file_tags(event.test_case)
              )
            end

            test_span = test_visibility_component.trace_test(
              event.test_case.name,
              test_suite_name,
              tags: tags,
              service: datadog_configuration[:service_name]
            )
            if event.test_case.match_tags?("@#{CI::Ext::Test::ITR_UNSKIPPABLE_OPTION}")
              test_span&.itr_unskippable!
            end
          end

          def on_test_case_finished(event)
            test_span = test_visibility_component.active_test
            return if test_span.nil?

            finish_span(test_span, event.result)
          end

          def on_test_step_started(event)
            test_visibility_component.trace(event.test_step.to_s, type: Ext::STEP_SPAN_TYPE)
          end

          def on_test_step_finished(event)
            current_step_span = test_visibility_component.active_span
            return if current_step_span.nil?

            finish_span(current_step_span, event.result)
          end

          private

          def test_suite_name(test_case)
            feature = if test_case.respond_to?(:feature)
              test_case.feature
            else
              @ast_lookup&.gherkin_document(test_case.location.file)&.feature
            end

            if feature
              "#{feature.name} at #{test_case.location.file}"
            else
              test_case.location.file
            end
          end

          def finish_span(span, result)
            if !result.passed? && ok?(result, @config.strict)
              span.skipped!(reason: result.message)
            elsif result.passed?
              span.passed!
            else
              span.failed!(exception: result.exception)
            end
            span.finish
          end

          def finish_session(result)
            test_session = test_visibility_component.active_test_session
            test_module = test_visibility_component.active_test_module

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

          def start_test_suite(test_suite_name, tags: {})
            finish_current_test_suite

            @current_test_suite = test_visibility_component.start_test_suite(test_suite_name, tags: tags)
          end

          def finish_current_test_suite
            @current_test_suite&.finish
            @failed_test_suites_count += 1 if @current_test_suite&.failed?

            @current_test_suite = nil
          end

          def same_test_suite_as_current?(test_suite_name)
            @current_test_suite&.name == test_suite_name
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

          def ok?(result, strict)
            # in minor update in Cucumber 9.2.0, the arity of the `ok?` method changed
            parameters = result.method(:ok?).parameters
            if parameters == [%i[opt be_strict]]
              result.ok?(strict)
            else
              result.ok?(strict: strict)
            end
          end

          def datadog_integration
            CI::Contrib::Instrumentation.fetch_integration(:cucumber)
          end

          def datadog_configuration
            Datadog.configuration.ci[:cucumber]
          end

          def test_visibility_component
            Datadog.send(:components).test_visibility
          end

          def test_suite_source_file_tags(test_case)
            if test_case.respond_to?(:parent_locations)
              # supported in cucumber >= 9.0
              source_file = test_case.parent_locations.file
              line_number = test_case.parent_locations.line.to_s
            else
              # fallback for cucumber < 9.0
              source_file = test_case.location.file
              line_number = "1"
            end

            {
              CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(source_file),
              CI::Ext::Test::TAG_SOURCE_START => line_number.to_s
            }
          end
        end
      end
    end
  end
end
