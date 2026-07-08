# frozen_string_literal: true

require_relative "../../source_code/constant_resolver"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Helpers
          module RunnableClassMethods
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

            def dd_any_unskippable?
              dd_suite_unskippable? || !!@datadog_itr_unskippable_tests
            end
          end

          def self.start_test_suite(klass)
            method = klass.runnable_methods.first
            return nil if method.nil?

            test_suite_name = test_suite_name(klass, method)
            source_file, line_number = extract_runnable_source_location(klass, method)

            test_suite_tags = if source_file
              {
                CI::Ext::Test::TAG_SOURCE_FILE => (Git::LocalRepository.relative_to_root(source_file) if source_file),
                CI::Ext::Test::TAG_SOURCE_START => line_number&.to_s
              }
            else
              {}
            end
            if klass.dd_any_unskippable?
              test_suite_tags[CI::Ext::Test::TAG_ITR_UNSKIPPABLE] = "true"
            end

            test_tracing_component = Datadog.send(:components).test_tracing
            test_suite = test_tracing_component.start_test_suite(
              test_suite_name,
              tags: test_suite_tags
            )
            test_suite&.set_expected_tests!(klass.runnable_methods)

            test_suite
          end

          def self.test_suite_name(klass, method_name)
            source_location = extract_runnable_source_location(klass, method_name)&.first

            # According to https://github.com/DataDog/datadog-ci-rb/issues/386
            # the source file path coould be relative when using minitest mixins.
            #
            # Note that it doesn't break for test suite source location in .start_test_suite method
            # because it outputs path relative to the repository root.
            #
            # For backwards compatibility, we'll continue to use the relative path from the current
            # working directory for test suite name.
            source_file_path = Pathname.new(source_location.to_s)
            if source_file_path.absolute?
              source_file_path = source_file_path.relative_path_from(Pathname.pwd).to_s
            end

            "#{klass.name} at #{source_file_path}"
          end

          def self.extract_runnable_source_location(klass, method_name)
            method_source_location = extract_source_location_from_method(klass, method_name)
            klass_source_location = extract_source_location_from_class(klass)

            if defined?(::Minitest::Spec) && klass&.ancestors&.include?(::Minitest::Spec)
              method_source_location || klass_source_location
            else
              klass_source_location || method_source_location
            end
          end

          def self.skip_test_suite(test_suite)
            test_suite&.finish
            []
          end

          def self.parallel?(klass)
            klass.ancestors.include?(::Minitest::Parallel::Test) || ci_queue?
          end

          def self.ci_queue?
            !!(defined?(::Minitest::Queue) && ::Minitest.singleton_class.ancestors.include?(::Minitest::Queue))
          end

          def self.extract_source_location_from_class(klass)
            return nil if klass.nil? || klass.name.nil?

            empty_source_location_to_nil(SourceCode::ConstantResolver.safely_get_const_source_location(klass.name))
          end

          def self.extract_source_location_from_method(klass, method_name)
            return nil if klass.nil?
            return nil if method_name.nil? || method_name.empty?

            empty_source_location_to_nil(klass.instance_method(method_name).source_location)
          end

          def self.empty_source_location_to_nil(source_location)
            return nil if source_location.nil? || source_location.empty?
            source_location
          end
        end
      end
    end
  end
end
