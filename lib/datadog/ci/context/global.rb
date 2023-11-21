# frozen_string_literal: true

module Datadog
  module CI
    module Context
      # This context is shared between threads and represents the current test session.
      class Global
        def initialize
          @mutex = Mutex.new
          @test_session = nil
        end

        def active_test_session
          @test_session
        end

        def activate_test_session!(test_session)
          @mutex.synchronize do
            raise "Nested test sessions are not supported. Currently active test session: #{@test_session}" unless @test_session.nil?

            @test_session = test_session
          end
        end

        def deactivate_test_session!
          @mutex.synchronize { @test_session = nil }
        end
      end
    end
  end
end
