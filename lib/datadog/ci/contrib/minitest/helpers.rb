# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        module Helpers
          def self.test_suite_name(klass, method_name)
            source_location, = klass.instance_method(method_name).source_location
            source_file_path = Pathname.new(source_location.to_s).relative_path_from(Pathname.pwd).to_s

            "#{klass.name} at #{source_file_path}"
          end

          def self.parallel?(klass)
            klass.ancestors.include?(::Minitest::Parallel::Test)
          end
        end
      end
    end
  end
end
