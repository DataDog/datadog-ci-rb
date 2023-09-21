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
            "_dd.origin" => "ciapp-test"
          }
        )
        # TODO: test start and duration with timecop
        # expect(content["start"]).to eq(1)
        # expect(content["duration"]).to eq(1)
        #
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
  end
end
