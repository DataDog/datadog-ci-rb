require_relative "../../../../../lib/datadog/ci/test_visibility/serializers/test_v1"
require_relative "../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers::TestV1 do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "Test visibility event serialized" do
    subject { described_class.new(trace, span) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_trace
      end

      it "serializes test event to messagepack" do
        expect_event_header

        expect(content).to include(
          {
            "trace_id" => trace.id,
            "span_id" => span.id,
            "name" => "rspec.test",
            "service" => "rspec-test-suite",
            "type" => "test",
            "resource" => "calculator_tests.test_add"
          }
        )

        expect(meta).to include(
          {
            "test.framework" => "rspec",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test",
            "test_owner" => "my_team"
          }
        )
        expect(metrics).to eq(
          {"_dd.measured" => 1.0, "_dd.top_level" => 1.0, "memory_allocations" => 16}
        )
      end
    end

    context "trace a failed test" do
      before do
        produce_test_trace(result: "FAILED", exception: StandardError.new("1 + 2 are not equal to 5"))
      end

      it "has error" do
        expect_event_header

        expect(content).to include({"error" => 1})
        expect(meta).to include({"test.status" => "fail"})
      end
    end

    context "with time and duration expectations" do
      let(:start_time) { Time.now }
      let(:duration_seconds) { 3 }

      before do
        produce_test_trace(start_time: start_time, duration_seconds: duration_seconds)
      end

      it "correctly serializes start and duration in nanoseconds" do
        expect(content).to include({
          "start" => start_time.to_i * 1_000_000_000 + start_time.nsec,
          "duration" => 3 * 1_000_000_000
        })
      end
    end
  end
end
