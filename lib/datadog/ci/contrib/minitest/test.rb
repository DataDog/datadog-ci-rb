# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../instrumentation"
require_relative "ext"
require_relative "helpers"

module Datadog
  module CI
    module Contrib
      module Minitest
        # Lifecycle hooks to instrument Minitest::Test
        module Test
          def self.included(base)
            base.prepend(InstanceMethods)
            base.singleton_class.prepend(ClassMethods)
          end

          module InstanceMethods
            def before_setup
              super
              return unless datadog_configuration[:enabled]

              test_suite_name = Helpers.test_suite_name(self.class, name)
              if Helpers.parallel?(self.class)
                test_suite_name = "#{test_suite_name} (#{name} concurrently)"

                # for parallel execution we need to start a new test suite for each test
                test_visibility_component.start_test_suite(test_suite_name)
              end

              source_file, line_number = method(name).source_location

              test_span = test_visibility_component.trace_test(
                name,
                test_suite_name,
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s,
                  CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(source_file),
                  CI::Ext::Test::TAG_SOURCE_START => line_number.to_s
                },
                service: datadog_configuration[:service_name]
              )
              test_span&.itr_unskippable! if self.class.dd_suite_unskippable? || self.class.dd_test_unskippable?(name)
              skip(test_span&.datadog_skip_reason) if test_span&.should_skip?
            end

            def after_teardown
              test_span = test_visibility_component.active_test
              return super unless test_span

              finish_with_result(test_span, result_code)

              # remove failures if test passed at least once on retries or quarantined
              self.failures = [] if test_span.should_ignore_failures?

              if Helpers.parallel?(self.class)
                finish_with_result(test_span.test_suite, result_code)
              end

              super
            end

            private

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

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end
          end

          module ClassMethods
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
              return false unless @datadog_itr_unskippable_tests

              @datadog_itr_unskippable_tests.include?(test_name)
            end
          end
        end
      end
    end
  end
end
