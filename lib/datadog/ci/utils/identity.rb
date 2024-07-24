# frozen_string_literal: true

module Datadog
  module CI
    module Utils
      module Identity
        def self.included(base)
          base.singleton_class.prepend(ClassMethods)
        end

        module ClassMethods
          # return datadog-ci gem version instead of datadog gem version
          def gem_datadog_version
            Datadog::CI::VERSION::STRING
          end
        end
      end
    end
  end
end
