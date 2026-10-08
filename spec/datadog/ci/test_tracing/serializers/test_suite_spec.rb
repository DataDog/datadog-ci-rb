RSpec.describe Datadog::CI::TestTracing::Serializers::TestSuite do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "msgpack serializer" do
    subject { described_class.new(trace_for_span(first_test_suite_span), first_test_suite_span) }
  end

  describe "#to_msgpack" do
    context "with Test Impact Analysis" do
      let(:itr_enabled) { true }
      let(:tests_skipping_enabled) { true }
      let(:itr_skippable_tests) do
        Set.new(["calculator_tests.tia_skip_1.", "calculator_tests.tia_skip_2."])
      end

      before do
        session = Datadog::CI.start_test_session
        test_module = Datadog::CI.start_test_module("arithmetic")
        suite = Datadog::CI.start_test_suite("calculator_tests")
        other_suite = Datadog::CI.start_test_suite("other_tests")

        ["tia_skip_1", "tia_skip_2", "framework_skip", "passing"].each do |name|
          Datadog::CI.trace_test(name, "calculator_tests") do |test|
            if test.should_skip? || name == "framework_skip"
              test.skipped!
            else
              test.passed!
            end
          end
        end
        Datadog::CI.trace_test("framework_skip", "other_tests") { |test| test.skipped! }

        suite.finish
        other_suite.finish
        test_module.finish
        session.finish
      end

      it "serializes the suite's TIA skip count and boolean independently of framework skips" do
        expect(meta).to include("_dd.ci.itr.tests_skipped" => "true")
        expect(metrics).to include("test.itr.tests_skipping.count" => 2)
        expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 2)

        other_suite_span = test_suite_spans.find { |span| span.get_tag("test.suite") == "other_tests" }
        other_event = MessagePack.unpack(MessagePack.pack(
          described_class.new(trace_for_span(other_suite_span), other_suite_span)
        ))
        expect(other_event["content"]["meta"]).to include("_dd.ci.itr.tests_skipped" => "false")
        expect(other_event["content"]["metrics"]).to include("test.itr.tests_skipping.count" => 0)
      end

      context "when test skipping is disabled" do
        let(:tests_skipping_enabled) { false }

        it "serializes zero skips and false" do
          expect(meta).to include("_dd.ci.itr.tests_skipped" => "false")
          expect(metrics).to include("test.itr.tests_skipping.count" => 0)
        end
      end

      context "when Test Impact Analysis is disabled" do
        let(:itr_enabled) { false }

        it "omits both suite tags" do
          expect(meta).not_to have_key("_dd.ci.itr.tests_skipped")
          expect(metrics).not_to have_key("test.itr.tests_skipping.count")
        end
      end
    end

    context "traced a single test execution with test visibility" do
      before do
        produce_test_session_trace
      end

      it "serializes test suite event to messagepack" do
        expect_event_header(type: Datadog::CI::Ext::AppTypes::TYPE_TEST_SUITE)

        expect(content).to include(
          {
            "test_session_id" => test_session_span.id,
            "test_module_id" => test_module_span.id,
            "test_suite_id" => first_test_suite_span.id,
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
        it { is_expected.to be_valid }
      end

      context "when test_session_id is nil" do
        before do
          first_test_suite_span.clear_tag("_test.session_id")
        end

        it { is_expected.not_to be_valid }
      end
    end

    context "test_module_id" do
      before do
        produce_test_session_trace
      end

      context "when test_module_id is not nil" do
        it { is_expected.to be_valid }
      end

      context "when test_module_id is nil" do
        before do
          first_test_suite_span.clear_tag("_test.module_id")
        end

        it { is_expected.not_to be_valid }
      end
    end

    context "test_suite_id" do
      before do
        produce_test_session_trace
      end

      context "when test_suite_id is not nil" do
        it { is_expected.to be_valid }
      end

      context "when test_suite_id is nil" do
        before do
          first_test_suite_span.clear_tag("_test.suite_id")
        end

        it { is_expected.not_to be_valid }
      end
    end
  end
end
