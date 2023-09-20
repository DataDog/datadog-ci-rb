require_relative "../../../../lib/datadog/ci/test_visibility/serializers"
require_relative "../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  subject { described_class.convert_trace_to_serializable_events(trace) }

  describe ".convert_trace_to_serializable_events" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_trace(with_http_span: true)
      end

      let(:payload) { MessagePack.unpack(MessagePack.pack(subject)) }

      it "converts trace to an array of serializable events" do
        expect(subject.count).to eq(2)
      end

      context "test event is present" do
        let(:test_event) { subject.find { |event| event.type == "test" } }

        it "contains test span" do
          expect(test_event.span_id).to eq(first_test_span.id)
        end
      end

      context "span event is present" do
        let(:span_event) { subject.find { |event| event.type == "span" } }

        it "contains http span" do
          expect(span_event.span_id).to eq(first_other_span.id)
        end
      end
    end
  end
end
