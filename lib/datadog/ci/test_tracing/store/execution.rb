# frozen_string_literal: true

module Datadog
  module CI
    module TestTracing
      module Store
        # One active test, visible only to its execution fiber. Instance-owned
        # storage avoids leaking a test into a replacement component.
        class Execution
          def initialize
            @pid = ::Process.pid
            @fiber = nil
            @test = nil
          end

          def activate_test(test)
            if block_given?
              begin
                self.active_test = test
                yield
              ensure
                deactivate_test
              end
            else
              self.active_test = test
            end
          end

          def deactivate_test
            @test = nil if @pid == ::Process.pid && @fiber.equal?(Fiber.current)
          end

          def active_test
            @test if @pid == ::Process.pid && @fiber.equal?(Fiber.current)
          end

          private

          def active_test=(test)
            @pid = ::Process.pid
            @fiber = Fiber.current
            @test = test
          end
        end
      end
    end
  end
end
