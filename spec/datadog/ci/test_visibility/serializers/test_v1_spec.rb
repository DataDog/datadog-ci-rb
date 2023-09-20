require_relative "../../../../../lib/datadog/ci/test_visibility/serializers/test_v1"
require_relative "../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers::TestV1 do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  subject { described_class.new(trace, span) }

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_trace
      end

      let(:payload) { MessagePack.unpack(MessagePack.pack(subject)) }

      it "serializes test event to messagepack" do
        expect(payload).to include(
          {
            "version" => 1,
            "type" => "test"
          }
        )
        content = payload["content"]
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

        tags = content["meta"]
        expect(tags).to include(
          {
            "test.framework" => "rspec",
            "_dd.origin" => "ciapp-test"
          }
        )
        # TODO: test start and duration with timecop
        # expect(content["start"]).to eq(1)
        # expect(content["duration"]).to eq(1)
        #
      end
    end
  end
end
