# frozen_string_literal: true

require_relative "../ext/environment"
require_relative "../ext/settings"
require_relative "transport"

module Datadog
  module CI
    module CodeCoverage
      # CodeCoverage component is responsible for uploading code coverage reports
      # to Datadog's Code Coverage product.
      class Component
        COVERAGE_REPORT_TYPE = "coverage_report"
        MAX_REPORT_FLAGS = 32

        attr_reader :enabled

        def initialize(enabled:, transport:)
          @enabled = enabled
          @transport = transport
          @flags = parse_flags(ENV[Ext::Settings::ENV_CODE_COVERAGE_FLAGS])
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
          event = {
            "type" => COVERAGE_REPORT_TYPE,
            "format" => format
          }.merge(Ext::Environment.tags(ENV))

          event["report.flags"] = @flags if @flags
          event
        end

        def parse_flags(value)
          return if value.nil?

          flags = value.split(",").map(&:strip).reject(&:empty?)
          return if flags.empty?

          if flags.length > MAX_REPORT_FLAGS
            Datadog.logger.warn(
              "#{Ext::Settings::ENV_CODE_COVERAGE_FLAGS} contains #{flags.length} flags, " \
              "but only #{MAX_REPORT_FLAGS} are allowed; omitting report flags"
            )
            return
          end

          flags.freeze
        end
      end
    end
  end
end
