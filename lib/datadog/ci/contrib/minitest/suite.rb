# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Minitest
        # Minitest integration constants
        # TODO: mark as `@public_api` when GA, to protect from resource and tag name changes.
        module Suite
          def self.name(klass, method_name)
            source_location, = klass.instance_method(method_name).source_location
            source_file_path = Pathname.new(source_location.to_s).relative_path_from(Pathname.pwd).to_s

            "#{klass.name} at #{source_file_path}"
          end
        end
      end
    end
  end
end
