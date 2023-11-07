# frozen_string_literal: true

require "datadog/core/utils/sequence"

module Datadog
  module CI
    module Context
      class Local
        def initialize
          @key = "datadog_ci_active_test_#{Local.next_instance_id}"
        end

        def activate_test!(test)
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

        def deactivate_test!(test)
          return if active_test.nil?

          if active_test == test
            self.active_test = nil
          else
            raise "Trying to deactivate test #{test}, but currently active test is #{active_test}"
          end
        end

        def active_test
          Thread.current[@key]
        end

        UNIQUE_INSTANCE_MUTEX = Mutex.new
        UNIQUE_INSTANCE_GENERATOR = Datadog::Core::Utils::Sequence.new

        private_constant :UNIQUE_INSTANCE_MUTEX, :UNIQUE_INSTANCE_GENERATOR

        def self.next_instance_id
          UNIQUE_INSTANCE_MUTEX.synchronize { UNIQUE_INSTANCE_GENERATOR.next }
        end

        private

        def active_test=(test)
          Thread.current[@key] = test
        end
      end
    end
  end
end
