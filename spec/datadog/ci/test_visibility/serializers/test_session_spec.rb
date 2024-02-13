RSpec.describe Datadog::CI::TestVisibility::Serializers::TestSession do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "citestcycle serializer" do
    subject { described_class.new(trace_for_span(test_session_span), test_session_span) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_session_trace
      end

      it "serializes test event to messagepack" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION)

        expect(content).to include(
          {
            "test_session_id" => test_session_span.id,
            "name" => "rspec.test_session",
            "service" => "rspec-test-suite",
            "type" => Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION,
            "resource" => "rspec.test_session.#{test_command}"
          }
        )

        expect(meta).to include(
          {
            "test.command" => test_command,
            "test.framework" => "rspec",
            "test.framework_version" => "1.0.0",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test"
          }
        )

        expect(meta["_test.session_id"]).to be_nil
      end
    end

    context "trace a failed test" do
      before do
        produce_test_session_trace(result: "FAILED", exception: StandardError.new("1 + 2 are not equal to 5"))
      end

      it "has error" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_SESSION)

        expect(content).to include({"error" => 1})
        expect(meta).to include({"test.status" => "fail"})
      end
    end
  end

  describe "#valid?" do
    context "test_session_id" do
      before do
        produce_test_session_trace
      end

      context "when test_session_id is not nil" do
        it { is_expected.to be_valid }
      end

      context "when test_session_id is nil" do
        before do
          test_session_span.clear_tag("_test.session_id")
        end

        it { is_expected.not_to be_valid }
      end
    end
  end
end
