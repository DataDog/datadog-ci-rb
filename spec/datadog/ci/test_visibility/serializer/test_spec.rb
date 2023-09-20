require_relative "../../../../../lib/datadog/ci/test_visibility/serializer/test"
require_relative "../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializer::Test do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  subject { Datadog::CI::TestVisibility::Serializer::Test.new(trace, span) }

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        Datadog::CI::Recorder.trace(
          "rspec.example",
          {
            span_options: {
              resource: "test_add",
              service: "rspec-test-suite"
            },
            framework: "rspec",
            framework_version: "3.0.0",
            test_name: "test_add",
            test_suite: "calculator_tests.rb",
            test_type: "test"
          }
        ) do |span|
          Datadog::CI::Recorder.passed!(span)
        end
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
            "type" => "test"
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
