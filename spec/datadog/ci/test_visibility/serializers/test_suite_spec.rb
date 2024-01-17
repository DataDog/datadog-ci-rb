RSpec.describe Datadog::CI::TestVisibility::Serializers::TestSuite do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "Test visibility event serialized" do
    subject { described_class.new(trace_for_span(test_suite_span), test_suite_span) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_session_trace
      end

      it "serializes test suite event to messagepack" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE)

        expect(content).to include(
          {
            "test_session_id" => test_session_span.id,
            "test_module_id" => test_module_span.id,
            "test_suite_id" => test_suite_span.id,
            "name" => "rspec.test_suite",
            "error" => 0,
            "service" => "rspec-test-suite",
            "type" => Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE,
            "resource" => "rspec.test_suite.calculator_tests"
          }
        )

        expect(meta).to include(
          {
            "test.command" => test_command,
            "test.module" => "arithmetic",
            "test.suite" => "calculator_tests",
            "test.framework" => "rspec",
            "test.framework_version" => "1.0.0",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test"
          }
        )

        expect(meta["_test.session_id"]).to be_nil
        expect(meta["_test.module_id"]).to be_nil
        expect(meta["_test.suite_id"]).to be_nil
      end
    end

    context "trace a failed test" do
      before do
        produce_test_session_trace(result: "FAILED", exception: StandardError.new("1 + 2 are not equal to 5"))
      end

      it "has error" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE)

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
        it "returns true" do
          expect(subject.valid?).to eq(true)
        end
      end

      context "when test_session_id is nil" do
        before do
          test_suite_span.clear_tag("_test.session_id")
        end

        it "returns false" do
          expect(subject.valid?).to eq(false)
        end
      end
    end

    context "test_module_id" do
      before do
        produce_test_session_trace
      end

      context "when test_module_id is not nil" do
        it "returns true" do
          expect(subject.valid?).to eq(true)
        end
      end

      context "when test_module_id is nil" do
        before do
          test_suite_span.clear_tag("_test.module_id")
        end

        it "returns false" do
          expect(subject.valid?).to eq(false)
        end
      end
    end

    context "test_suite_id" do
      before do
        produce_test_session_trace
      end

      context "when test_suite_id is not nil" do
        it "returns true" do
          expect(subject.valid?).to eq(true)
        end
      end

      context "when test_suite_id is nil" do
        before do
          test_suite_span.clear_tag("_test.suite_id")
        end

        it "returns false" do
          expect(subject.valid?).to eq(false)
        end
      end
    end
  end
end
