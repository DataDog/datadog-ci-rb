# frozen_string_literal: true

require_relative "../../utils/json"

module Datadog
  module CI
    module TestOptimizationCache
      module Readers
        class Base
          def available?
            true
          end

          def load_settings
            raise NotImplementedError, "#{self.class} must implement #load_settings"
          end

          def load_known_tests
            raise NotImplementedError, "#{self.class} must implement #load_known_tests"
          end

          def load_test_management
            raise NotImplementedError, "#{self.class} must implement #load_test_management"
          end

          def load_skippable_tests
            raise NotImplementedError, "#{self.class} must implement #load_skippable_tests"
          end

          private

          def read_json_file(file_path)
            Utils::Json.read_file(file_path)
          end
        end
      end
    end
  end
end
