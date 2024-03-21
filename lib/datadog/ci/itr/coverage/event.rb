# frozen_string_literal: true

module Datadog
  module CI
    module ITR
      module Coverage
        class Event
          attr_reader :test_id, :test_suite_id, :test_session_id, :coverage

          def initialize(test_id:, test_suite_id:, test_session_id:, coverage:)
            @test_id = test_id
            @test_suite_id = test_suite_id
            @test_session_id = test_session_id
            @coverage = coverage
          end
        end
      end
    end
  end
end
