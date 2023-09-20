require_relative "../../../../../lib/datadog/ci/test_visibility/serializers/span"
require_relative "../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers::Span do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  let(:test_span) do
    spans.find { |span| span.type == "test" }
  end

  let(:tracer_span) do
    spans.find { |span| span.type != "test" }
  end

  subject { described_class.new(trace, tracer_span) }

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_trace(with_http_span: true)
      end

      let(:payload) { MessagePack.unpack(MessagePack.pack(subject)) }

      it "serializes test event to messagepack" do
        expect(payload).to include(
          {
            "version" => 1,
            "type" => "span"
          }
        )
        content = payload["content"]
        expect(content).to include(
          {
            "trace_id" => trace.id,
            "span_id" => first_other_span.id,
            "parent_id" => first_test_span.id,
            "name" => "http-call",
            "service" => "net-http",
            "type" => "http",
            "error" => 0,
            "resource" => "http-call"
          }
        )

        tags = content["meta"]
        expect(tags).to include(
          {
            "custom_tag" => "custom_tag_value",
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
