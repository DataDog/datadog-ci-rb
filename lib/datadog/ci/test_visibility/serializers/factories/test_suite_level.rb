# frozen_string_literal: true

require_relative "../test_v2"
require_relative "../test_session"
require_relative "../test_module"
require_relative "../test_suite"
require_relative "../span"

module Datadog
  module CI
    module TestVisibility
      module Serializers
        module Factories
          # This factory takes care of creating msgpack serializers when test-suite-level visibility is enabled
          module TestSuiteLevel
            module_function

            def serializer(trace, span)
              case span.type
              when Datadog::CI::Ext::AppTypes::TYPE_TEST
                Serializers::TestV2.new(trace, span)
              when Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION
                Serializers::TestSession.new(trace, span)
              when Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE
                Serializers::TestModule.new(trace, span)
              when Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE
                Serializers::TestSuite.new(trace, span)
              else
                Serializers::Span.new(trace, span)
              end
            end
          end
        end
      end
    end
  end
end
