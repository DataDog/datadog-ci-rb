# frozen_string_literal: true

module Datadog
  module CI
    module Ext
      module AppTypes
        TYPE_TEST = "test"
        TYPE_TEST_SESSION = "test_session_end"

        CI_SPAN_TYPES = [TYPE_TEST, TYPE_TEST_SESSION].freeze
      end
    end
  end
end
