# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "../../git/local_repository"
require_relative "../../utils/source_code"
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

              if Helpers.parallel?(self.class)
                Helpers.start_test_suite(self.class)
              end

              test_suite_name = Helpers.test_suite_name(self.class, name)

              test_method = method(name)
              source_file, first_line_number = test_method.source_location
              last_line_number = Utils::SourceCode.last_line(test_method)

              # @type var tags : Hash[String, String]
              tags = {
                CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                CI::Ext::Test::TAG_FRAMEWORK_VERSION => datadog_integration.version.to_s,
                CI::Ext::Test::TAG_SOURCE_FILE => Git::LocalRepository.relative_to_root(source_file),
                CI::Ext::Test::TAG_SOURCE_START => first_line_number.to_s
              }

              tags[CI::Ext::Test::TAG_SOURCE_END] = last_line_number.to_s if last_line_number

              test_span = test_visibility_component.trace_test(
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
              skip(test_span&.datadog_skip_reason) if test_span&.should_skip?
            end

            def after_teardown
              test_span = test_visibility_component.active_test
              return super unless test_span

              finish_with_result(test_span, result_code)

              # remove failures if test passed at least once on retries or quarantined
              self.failures = [] if test_span.should_ignore_failures?

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
