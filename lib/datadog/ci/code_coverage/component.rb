# frozen_string_literal: true

require_relative "../ext/environment"
require_relative "transport"

module Datadog
  module CI
    module CodeCoverage
      # CodeCoverage component is responsible for uploading code coverage reports
      # to Datadog's Code Coverage product.
      class Component
        COVERAGE_REPORT_TYPE = "coverage_report"

        attr_reader :enabled

        def initialize(enabled:, transport:)
          @enabled = enabled
          @transport = transport
        end

        def configure(library_configuration)
          @enabled &&= library_configuration.coverage_report_upload_enabled?

          Datadog.logger.debug do
            "[#{self.class.name}] Configured with enabled=#{@enabled}"
          end
        end

        def upload(serialized_report:, format:)
          return unless @enabled
          return if serialized_report.nil?

          Datadog.logger.debug { "[#{self.class.name}] Uploading coverage report..." }

          event = build_event(format)

          @transport.send_coverage_report(event: event, coverage_report: serialized_report)
        end

        def shutdown!
          # noop - transport is synchronous
        end

        private

        def build_event(format)
          {
            "type" => COVERAGE_REPORT_TYPE,
            "format" => format
          }.merge(Ext::Environment.tags(DATADOG_ENV))
        end
      end
    end
  end
end
