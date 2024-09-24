require_relative "helpers"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Runnable
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def run(*args)
              return super unless datadog_configuration[:enabled]
              return super if Helpers.parallel?(self)

              method = runnable_methods.first
              return super if method.nil?

              test_suite_name = Helpers.test_suite_name(self, method)
              source_file, line_number = Helpers.extract_source_location_from_class(self)

              test_suite_tags = if source_file
                {
                  CI::Ext::Test::TAG_SOURCE_FILE => (Git::LocalRepository.relative_to_root(source_file) if source_file),
                  CI::Ext::Test::TAG_SOURCE_START => line_number&.to_s
                }
              else
                {}
              end

              test_suite = test_visibility_component.start_test_suite(
                test_suite_name,
                tags: test_suite_tags
              )

              results = super
              return results unless test_suite

              test_suite.finish

              results
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end
          end
        end
      end
    end
  end
end
