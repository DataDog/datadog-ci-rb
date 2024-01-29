# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        module Helpers
          def self.test_suite_name(klass, method_name)
            source_location = extract_source_location_from_class(klass)
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
            return nil if klass.nil? || klass.name.nil?

            klass.const_source_location(klass.name)&.first
          rescue
            nil
          end
        end
      end
    end
  end
end
