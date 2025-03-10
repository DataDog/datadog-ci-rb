# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        module Helpers
          def self.start_test_suite(klass)
            method = klass.runnable_methods.first
            return nil if method.nil?

            test_suite_name = test_suite_name(klass, method)
            source_file, line_number = extract_source_location_from_class(klass)

            test_suite_tags = if source_file
              {
                CI::Ext::Test::TAG_SOURCE_FILE => (Git::LocalRepository.relative_to_root(source_file) if source_file),
                CI::Ext::Test::TAG_SOURCE_START => line_number&.to_s
              }
            else
              {}
            end

            test_visibility_component = Datadog.send(:components).test_visibility
            test_suite = test_visibility_component.start_test_suite(
              test_suite_name,
              tags: test_suite_tags
            )
            test_suite&.set_expected_tests!(klass.runnable_methods)

            test_suite
          end

          def self.test_suite_name(klass, method_name)
            source_location = extract_source_location_from_class(klass)&.first
            # if we are in anonymous class, fallback to the method source location
            if source_location.nil?
              source_location, = klass.instance_method(method_name).source_location
            end

            source_file_path = Pathname.new(source_location.to_s).relative_path_from(Pathname.pwd).to_s

            "#{klass.name} at #{source_file_path}"
          end

          def self.parallel?(klass)
            klass.ancestors.include?(::Minitest::Parallel::Test) ||
              (defined?(::Minitest::Queue) && ::Minitest.singleton_class.ancestors.include?(::Minitest::Queue))
          end

          def self.extract_source_location_from_class(klass)
            return [] if klass.nil? || klass.name.nil?

            klass.const_source_location(klass.name)
          rescue
            []
          end
        end
      end
    end
  end
end
