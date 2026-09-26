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
            @pid = ::Process.pid
            @fiber = Fiber.current
            @test = test
            return unless block_given?

            begin
              yield
            ensure
              deactivate_test
            end
          end

          def deactivate_test
            @test = nil if @pid == ::Process.pid && @fiber.equal?(Fiber.current)
          end

          def active_test
            @test if @pid == ::Process.pid && @fiber.equal?(Fiber.current)
          end
        end
      end
    end
  end
end
