# frozen_string_literal: true

require_relative "../../../../lib/datadog/ci/code_coverage/transport"

RSpec.describe Datadog::CI::CodeCoverage::Transport do
  subject(:transport) { described_class.new(api: api) }

  let(:api) { spy(:api, cicovreprt_request: http_response) }
  let(:http_response) do
    instance_double(
      Datadog::CI::Transport::Adapters::Net::Response,
      ok?: true,
      telemetry_error_type: nil,
      code: 200,
      duration_ms: 1.5,
      request_compressed: true
    )
  end

  describe "#send_coverage_report" do
    subject(:send_coverage_report) { transport.send_coverage_report(event: event, coverage_report: coverage_report) }

    let(:event) { {"type" => "coverage_report", "format" => "simplecov-internal"} }
    let(:coverage_report) { '{"file.rb": [1, 2, 3]}' }

    context "when api is nil" do
      let(:api) { nil }

      it "returns nil" do
        expect(send_coverage_report).to be_nil
      end
    end

    context "when api is present" do
      it "sends the coverage report" do
        send_coverage_report

        expect(api).to have_received(:cicovreprt_request).with(
          path: Datadog::CI::Ext::Transport::CODE_COVERAGE_REPORT_INTAKE_PATH,
          event_payload: event.to_json,
          compressed_coverage_report: anything
        )
      end

      it "compresses the coverage data" do
        send_coverage_report

        expect(api).to have_received(:cicovreprt_request) do |args|
          # Check that coverage is gzip compressed
          expect(args[:compressed_coverage_report].bytes[0..1]).to eq([0x1F, 0x8B])
        end
      end

      it "returns the http response" do
        expect(send_coverage_report).to eq(http_response)
      end

      it "reports telemetry metrics" do
        expect(Datadog::CI::Transport::Telemetry).to receive(:api_requests).with(
          Datadog::CI::Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST,
          1,
          compressed: true
        )

        expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
          Datadog::CI::Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST_MS,
          1.5
        )

        expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).with(
          Datadog::CI::Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST_BYTES,
          kind_of(Float),
          {Datadog::CI::Ext::Telemetry::TAG_REQUEST_COMPRESSED => "true"}
        )

        send_coverage_report
      end

      context "when response is not ok" do
        let(:http_response) do
          instance_double(
            Datadog::CI::Transport::Adapters::Net::Response,
            ok?: false,
            telemetry_error_type: "status_code",
            code: 500,
            duration_ms: 2.0,
            request_compressed: true,
            inspect: "Response 500"
          )
        end

        it "reports error telemetry" do
          expect(Datadog::CI::Transport::Telemetry).to receive(:api_requests).with(
            Datadog::CI::Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST,
            1,
            compressed: true
          )
          expect(Datadog::CI::Utils::Telemetry).to receive(:distribution).twice

          expect(Datadog::CI::Transport::Telemetry).to receive(:api_requests_errors).with(
            Datadog::CI::Ext::Telemetry::METRIC_COVERAGE_UPLOAD_REQUEST_ERRORS,
            1,
            error_type: "status_code",
            status_code: 500
          )

          send_coverage_report
        end
      end
    end
  end
end
