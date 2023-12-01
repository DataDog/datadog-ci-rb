# frozen_string_literal: true

module Datadog
  module CI
    module Context
      # This context is shared between threads and represents the current test session and test module.
      class Global
        def initialize
          @mutex = Mutex.new
          @test_session = nil
          @test_module = nil
          @test_suites = {}
        end

        def fetch_or_activate_test_suite(test_suite_name, &block)
          @mutex.synchronize do
            @test_suites[test_suite_name] ||= block.call
          end
        end

        def active_test_module
          @test_module
        end

        def active_test_session
          @test_session
        end

        def active_test_suite(test_suite_name)
          @mutex.synchronize { @test_suites[test_suite_name] }
        end

        def service
          @mutex.synchronize do
            # thank you RBS for this weirdness
            test_session = @test_session
            test_session.service if test_session
          end
        end

        def inheritable_session_tags
          @mutex.synchronize do
            test_session = @test_session
            if test_session
              test_session.inheritable_tags
            else
              {}
            end
          end
        end

        def activate_test_session!(test_session)
          @mutex.synchronize do
            raise "Nested test sessions are not supported. Currently active test session: #{@test_session}" unless @test_session.nil?

            @test_session = test_session
          end
        end

        def activate_test_module!(test_module)
          @mutex.synchronize do
            raise "Nested test modules are not supported. Currently active test module: #{@test_module}" unless @test_module.nil?

            @test_module = test_module
          end
        end

        def deactivate_test_session!
          @mutex.synchronize { @test_session = nil }
        end

        def deactivate_test_module!
          @mutex.synchronize { @test_module = nil }
        end

        def deactivate_test_suite!(test_suite_name)
          @mutex.synchronize { @test_suites.delete(test_suite_name) }
        end
      end
    end
  end
end
