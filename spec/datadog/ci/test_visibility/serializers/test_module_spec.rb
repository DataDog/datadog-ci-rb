RSpec.describe Datadog::CI::TestVisibility::Serializers::TestModule do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "msgpack serializer" do
    subject { described_class.new(trace_for_span(test_module_span), test_module_span) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with test visibility" do
      before do
        produce_test_session_trace
      end

      it "serializes test module event to messagepack" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE)

        expect(content).to include(
          {
            "test_session_id" => test_session_span.id,
            "test_module_id" => test_module_span.id,
            "name" => "rspec.test_module",
            "service" => "rspec-test-suite",
            "type" => Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE,
            "resource" => "rspec.test_module.arithmetic"
          }
        )

        expect(meta).to include(
          {
            "test.command" => test_command,
            "test.module" => "arithmetic",
            "test.framework" => "rspec",
            "test.framework_version" => "1.0.0",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test"
          }
        )

        expect(meta["_test.session_id"]).to be_nil
        expect(meta["_test.module_id"]).to be_nil
      end
    end

    context "trace a failed test" do
      before do
        produce_test_session_trace(result: "FAILED", exception: StandardError.new("1 + 2 are not equal to 5"))
      end

      it "has error" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_MODULE)

        expect(content).to include({"error" => 1})
        expect(meta).to include({"test.status" => "fail"})
      end
    end
  end

  describe "#valid?" do
    before do
      produce_test_session_trace
    end

    context "test_session_id" do
      context "when test_session_id is not nil" do
        it { is_expected.to be_valid }
      end

      context "when test_session_id is nil" do
        before do
          test_module_span.clear_tag("_test.session_id")
          subject.valid?
        end

        it { is_expected.not_to be_valid }

        it "returns a correct validation error" do
          expect(subject.validation_errors["test_session_id"]).to include("is required")
        end
      end
    end

    context "test_module_id" do
      context "when test_module_id is not nil" do
        it { is_expected.to be_valid }
      end

      context "when test_module_id is nil" do
        before do
          test_module_span.clear_tag("_test.module_id")
          subject.valid?
        end

        it { is_expected.not_to be_valid }

        it "returns a correct validation error" do
          expect(subject.validation_errors["test_module_id"]).to include("is required")
        end
      end
    end
  end
end
