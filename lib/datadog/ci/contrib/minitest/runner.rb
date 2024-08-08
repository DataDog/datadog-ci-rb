# frozen_string_literal: true

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Runner
          def self.included(base)
            base.singleton_class.prepend(ClassMethods)
          end

          module ClassMethods
            def init_plugins(*args)
              super

              return unless datadog_configuration[:enabled]

              test_visibility_component.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Minitest::Integration.version.to_s
                },
                service: datadog_configuration[:service_name]
              )
              test_visibility_component.start_test_module(Ext::FRAMEWORK)
            end

            def run_one_method(klass, method_name)
              return super unless datadog_configuration[:enabled]

              result = nil
              # retries here
              test_retries_component.with_retries do |test_finished_callback|
                Thread.current[:__dd_retry_callback] = test_finished_callback

                result = super
              end
              result
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end

            def test_visibility_component
              Datadog.send(:components).test_visibility
            end

            def test_retries_component
              Datadog.send(:components).test_retries
            end
          end
        end
      end
    end
  end
end
