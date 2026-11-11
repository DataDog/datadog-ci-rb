# frozen_string_literal: true

require_relative "../../source_code/constant_resolver"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Helpers
          module RunnableClassMethods
            attr_accessor :dd_spec_source_file

            # Apply these declarations to named test methods, after defining them.
            def datadog_prevent_failure_suppression(*test_names)
              declarations = (@datadog_prevent_failure_suppression_tests ||= {})
              test_names.each do |test_name|
                declaration = dd_automation_exclusion_declaration(test_name)
                declarations[test_name.to_s] = declaration if declaration
              end
              nil
            end

            def datadog_no_auto_retry(*test_names)
              declarations = (@datadog_no_auto_retry_tests ||= {})
              test_names.each do |test_name|
                declaration = dd_automation_exclusion_declaration(test_name)
                declarations[test_name.to_s] = declaration if declaration
              end
              nil
            end

            def dd_test_prevent_failure_suppression?(test_name, declaration = dd_automation_exclusion_declaration(test_name))
              return false unless declaration
              return true if @datadog_prevent_failure_suppression_tests&.fetch(test_name.to_s, nil) == declaration

              # Class instance variables are not inherited. Search parents using
              # the child's method identity so overrides cannot inherit exclusions.
              # Steep cannot infer the exclusion API from respond_to?.
              # @type var parent : untyped
              parent = superclass
              parent.respond_to?(:dd_test_prevent_failure_suppression?) && parent.dd_test_prevent_failure_suppression?(test_name, declaration)
            end

            def dd_test_no_auto_retry?(test_name, declaration = dd_automation_exclusion_declaration(test_name))
              return false unless declaration
              return true if @datadog_no_auto_retry_tests&.fetch(test_name.to_s, nil) == declaration

              # Steep cannot infer the exclusion API from respond_to?.
              # @type var parent : untyped
              parent = superclass
              parent.respond_to?(:dd_test_no_auto_retry?) && parent.dd_test_no_auto_retry?(test_name, declaration)
            end

            def dd_automation_exclusion_declaration(test_name)
              unless method_defined?(test_name) || private_method_defined?(test_name)
                Datadog.logger.warn("Ignoring Datadog automation exclusion for undefined test method #{self}##{test_name}; define the method before declaring exclusions")
                return nil
              end

              declaration = instance_method(test_name)
              # On Ruby 2.7, Child.instance_method(:test) != Parent.instance_method(:test)
              # even when Child inherits the same implementation. Resolve through the
              # defining owner so inherited methods match and replacements do not.
              declaration.owner.instance_method(test_name)
            end

            def dd_clear_automation_exclusions(test_name)
              @datadog_prevent_failure_suppression_tests&.delete(test_name.to_s)
              @datadog_no_auto_retry_tests&.delete(test_name.to_s)
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

          def self.discovery_source_file(klass, method_name)
            spec_file = klass.dd_spec_source_file
            return extract_runnable_source_location(klass, method_name)&.first unless spec_file

            method = klass.instance_method(method_name)
            if method.owner == klass
              method.source_location&.first || spec_file
            else
              spec_file
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
