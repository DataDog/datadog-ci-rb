# frozen_string_literal: true

require "json"

require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/gzip"
require_relative "../transport/telemetry"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module CodeCoverage
      class Transport
        attr_reader :api

        def initialize(api:)
          @api = api
        end

        def send_coverage_report(event:, coverage_report:)
          return nil if api.nil?

          Datadog.logger.debug { "[#{self.class.name}] Sending coverage report..." }

          compressed_coverage_report = CI::Transport::Gzip.compress(coverage_report)
          event_json = event.to_json

          response = api.cicovreprt_request(
            path: Ext::Transport::CODE_COVERAGE_REPORT_INTAKE_PATH,
            event_payload: event_json,
            compressed_coverage_report: compressed_coverage_report
          )

          CI::Transport::Telemetry.api_requests(
            Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST,
            1,
            compressed: response.request_compressed
          )
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST_MS,
            response.duration_ms
          )
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST_BYTES,
            compressed_coverage_report.bytesize.to_f,
            {Ext::Telemetry::TAG_REQUEST_COMPRESSED => response.request_compressed.to_s}
          )

          unless response.ok?
            CI::Transport::Telemetry.api_requests_errors(
              Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST_ERRORS,
              1,
              error_type: response.telemetry_error_type,
              status_code: response.code
            )

            Datadog.logger.warn { "[#{self.class.name}] Failed to send coverage report: #{response.inspect}" }
          end

          response
        end
      end
    end
  end
end
