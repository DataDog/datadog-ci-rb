# frozen_string_literal: true

require "weakref"

require_relative "../../ext/test"
require_relative "ext"

module Datadog
  module CI
    module Contrib
      module Minitest
        module Plugin
          def self.included(base)
            base.extend(ClassMethods)
          end

          class DatadogReporter < ::Minitest::AbstractReporter
            def initialize(minitest_reporter)
              # This creates circular reference as minitest_reporter also holds reference to DatadogReporter.
              # To make sure that minitest_reporter can be garbage collected, we use WeakRef.
              @reporter = WeakRef.new(minitest_reporter)
            end

            def report
              active_test_session = CI.active_test_session
              active_test_module = CI.active_test_module

              return unless @reporter.weakref_alive?
              return if active_test_session.nil? || active_test_module.nil?

              if @reporter.passed?
                active_test_module.passed!
                active_test_session.passed!
              else
                active_test_module.failed!
                active_test_session.failed!
              end

              active_test_module.finish
              active_test_session.finish

              nil
            end
          end

          module ClassMethods
            def plugin_datadog_ci_init(*)
              return unless datadog_configuration[:enabled]

              test_session = CI.start_test_session(
                tags: {
                  CI::Ext::Test::TAG_FRAMEWORK => Ext::FRAMEWORK,
                  CI::Ext::Test::TAG_FRAMEWORK_VERSION => CI::Contrib::Minitest::Integration.version.to_s
                },
                service: datadog_configuration[:service_name]
              )
              CI.start_test_module(test_session.name)

              reporter.reporters << DatadogReporter.new(reporter)
            end

            private

            def datadog_configuration
              Datadog.configuration.ci[:minitest]
            end
          end
        end
      end
    end
  end
end
