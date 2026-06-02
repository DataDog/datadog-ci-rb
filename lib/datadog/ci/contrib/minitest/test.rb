# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../../source_code/method_inspect"
require_relative "../instrumentation"
require_relative "ext"
require_relative "helpers"
require_relative "run_method_capture"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Lifecycle hooks to instrument Minitest::Test
        module Test
          class << self
            attr_accessor :_dd_pre_datadog_minitest_run
          end

          def self.included(base)
            unless base < InstanceMethods
              # Preserve the run implementation that existed before Datadog was prepended.
              # RunMethodCapture repairs this if auto-instrumentation observes Minitest::Test
              # before Minitest defines its concrete #run. See that helper for the ci-queue
              # and minitest-reporters load-order details.
              self._dd_pre_datadog_minitest_run = base.instance_method(:run)
              base.prepend(InstanceMethods)
            end

            base.singleton_class.prepend(ClassMethods) unless base.singleton_class < ClassMethods
          end

          module InstanceMethods
            def run
              return super unless datadog_configuration[:enabled]

              return run_without_datadog_reentry if datadog_run_reentered?

              @_dd_minitest_run_in_progress = true
              begin
                @_dd_minitest_span_finished = false
                test_span = start_datadog_test
                @_dd_minitest_test_span = test_span
                return skip_datadog_test(test_span) if test_span&.should_skip?

                super
              ensure
                @_dd_minitest_test_span = nil
                @_dd_minitest_run_in_progress = false
              end
            end

            def after_teardown
              test_span = _dd_test_tracing_component.active_test
              return super unless test_span
              return super if @_dd_minitest_span_finished

              @_dd_minitest_span_finished = true
              finish_with_result(test_span, result_code)

              # remove failures if failure can be ignored because of retries
              self.failures = [] if test_span.should_ignore_failures?

              super
            end

            private

            def datadog_run_reentered?
              !!(@_dd_minitest_run_in_progress &&
                @_dd_minitest_test_span &&
                _dd_test_tracing_component.active_test.equal?(@_dd_minitest_test_span))
            end

            def run_without_datadog_reentry
              Datadog.logger.debug do
                "Datadog Minitest instrumentation re-entered for #{self.class}##{name}; running pre-Datadog Minitest run without starting another test span"
              end

              pre_datadog_minitest_run = Test._dd_pre_datadog_minitest_run
              if RunMethodCapture.concrete_pre_datadog_run?(pre_datadog_minitest_run, InstanceMethods)
                return pre_datadog_minitest_run.bind_call(self)
              end

              raise "Datadog Minitest instrumentation re-entered for #{self.class}##{name}, " \
                "but the concrete pre-Datadog Minitest::Test#run method was not captured"
            end

            def start_datadog_test
              if Helpers.parallel?(self.class)
                Helpers.start_test_suite(self.class)
              end

              test_suite_name = Helpers.test_suite_name(self.class, name)

              # @type var tags : Hash[String, String]
              tags = {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s
              }

              # try to find out where test method starts and ends
              test_method = method(name)
              source_file, first_line_number = test_method.source_location
              last_line_number = SourceCode::MethodInspect.last_line(test_method)

              tags[CI::Ext::Test::TAG_SOURCE_FILE] = Git::LocalRepository.relative_to_root(source_file) if source_file
              tags[CI::Ext::Test::TAG_SOURCE_START] = first_line_number.to_s if first_line_number
              tags[CI::Ext::Test::TAG_SOURCE_END] = last_line_number.to_s if last_line_number

              test_span = _dd_test_tracing_component.trace_test(
                name,
                test_suite_name,
                tags: tags,
                service: datadog_configuration[:service_name]
              )
              # Steep type checker doesn't know that we patched Minitest::Test class definition
              #
              # steep:ignore:start
              test_span&.itr_unskippable! if self.class.dd_suite_unskippable? || self.class.dd_test_unskippable?(name)
              # steep:ignore:end

              test_span
            end

            def skip_datadog_test(test_span)
              time_it do
                capture_exceptions do
                  skip(test_span.datadog_skip_reason)
                end
              end

              finish_with_result(test_span, result_code)

              ::Minitest::Result.from(self)
            end

            def finish_with_result(span, result_code)
              return unless span

              case result_code
              when "."
                span.passed!
              when "E", "F"
                span.failed!(exception: failure)
              when "S"
                span.skipped!(reason: failure.message)
              end

              span.finish
            end

            def datadog_integration
              CI::Contrib::Instrumentation.fetch_integration(:minitest)
            end

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def _dd_test_tracing_component
              Datadog.send(:components).test_tracing
            end
          end

          module ClassMethods
            def method_added(method_name)
              RunMethodCapture.capture_concrete_pre_datadog_run!(Test, self, InstanceMethods) if method_name == :run
            ensure
              super
            end

            def datadog_itr_unskippable(*args)
              if args.nil? || args.empty?
                @datadog_itr_unskippable_suite = true
              else
                @datadog_itr_unskippable_tests = args
              end
            end

            def dd_suite_unskippable?
              @datadog_itr_unskippable_suite
            end

            def dd_test_unskippable?(test_name)
              tests = @datadog_itr_unskippable_tests
              return false unless tests

              tests.include?(test_name)
            end
          end
        end
      end
    end
  end
end
