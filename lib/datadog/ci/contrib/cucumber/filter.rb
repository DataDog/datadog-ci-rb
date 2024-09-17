# frozen_string_literal: true

module Datadog
  module CI
    module Contrib
      module Cucumber
        class Filter < ::Cucumber::Core::Filter.new(:configuration)
          def test_case(test_case)
            test_retries_component.reset_retries! unless test_case_seen[test_case]

            test_case_seen[test_case] = true
            configuration.on_event(:test_case_finished) do |event|
              next unless retry_required?(test_case, event)

              test_case.describe_to(receiver)
            end

            super
          end

          private

          def retry_required?(test_case, event)
            return false unless event.test_case == test_case

            test_retries_component.should_retry?
          end

          def test_case_seen
            @test_case_seen ||= Hash.new { |h, k| h[k] = false }
          end

          def test_retries_component
            @test_retries_component ||= Datadog.send(:components).test_retries
          end
        end
      end
    end
  end
end
