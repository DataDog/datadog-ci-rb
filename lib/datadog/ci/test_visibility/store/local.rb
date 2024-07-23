# frozen_string_literal: true

module Datadog
  module CI
    module TestVisibility
      module Store
        class Local
          def initialize
            @key = :datadog_ci_active_test

            self.active_test = nil
          end

          def activate_test(test)
            raise "Nested tests are not supported. Currently active test: #{active_test}" unless active_test.nil?

            if block_given?
              begin
                self.active_test = test
                yield
              ensure
                self.active_test = nil
              end
            else
              self.active_test = test
            end
          end

          def deactivate_test
            self.active_test = nil
          end

          def active_test
            Thread.current[@key]
          end

          private

          def active_test=(test)
            Thread.current[@key] = test
          end
        end
      end
    end
  end
end
