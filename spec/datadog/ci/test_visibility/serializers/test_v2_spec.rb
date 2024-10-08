require_relative "../../../../../lib/datadog/ci/test_visibility/serializers/test_v2"
require_relative "../../../../../lib/datadog/ci/test_visibility/component"

RSpec.describe Datadog::CI::TestVisibility::Serializers::TestV2 do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  let(:options) { {} }
  include_context "msgpack serializer" do
    subject { described_class.new(trace_for_span(first_test_span), first_test_span, options: options) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with test visibility" do
      before do
        produce_test_session_trace
      end

      it "serializes test event to messagepack" do
        expect_event_header(version: 2)

        expect(content).to include(
          {
            "trace_id" => first_test_span.trace_id,
            "span_id" => first_test_span.id,
            "name" => "rspec.test",
            "service" => "rspec-test-suite",
            "type" => "test",
            "resource" => "calculator_tests.test_add.run.0",
            "test_session_id" => test_session_span.id,
            "test_module_id" => test_module_span.id,
            "test_suite_id" => first_test_suite_span.id
          }
        )

        expect(meta).to include(
          {
            "test.name" => "test_add.run.0",
            "test.framework" => "rspec",
            "test.framework_version" => "1.0.0",
            "test.suite" => "calculator_tests",
            "test.module" => "arithmetic",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test",
            "test_owner" => "my_team"
          }
        )
        expect(meta["_test.session_id"]).to be_nil
        expect(meta["_test.module_id"]).to be_nil

        expect(metrics).to eq({"_dd.top_level" => 1, "memory_allocations" => 16, "_dd.host.vcpu_count" => Etc.nprocessors})
      end
    end

    context "trace several tests executions with test visibility" do
      let(:test_spans) { spans.select { |span| span.type == "test" } }
      subject { test_spans.map { |span| described_class.new(trace_for_span(span), span) } }

      before do
        produce_test_session_trace(tests_count: 2)
      end

      it "serializes both tests to msgpack" do
        msgpack_jsons.each_with_index do |msgpack_json, index|
          expect(msgpack_json["content"]).to include(
            {
              "trace_id" => test_spans[index].trace_id,
              "span_id" => test_spans[index].id,
              "name" => "rspec.test",
              "service" => "rspec-test-suite",
              "type" => "test",
              "resource" => "calculator_tests.test_add.run.#{index}",
              "test_session_id" => test_session_span.id
            }
          )
        end
      end

      it "all tests have different trace ids" do
        unique_trace_ids = msgpack_jsons.map { |msgpack_json| msgpack_json["content"]["trace_id"] }.uniq
        expect(unique_trace_ids.size).to eq(2)
      end
    end

    context "trace a failed test" do
      before do
        produce_test_session_trace(result: "FAILED", exception: StandardError.new("1 + 2 are not equal to 5"))
      end

      it "has error" do
        expect_event_header(version: 2)

        expect(content).to include({"error" => 1})
        expect(meta).to include({"test.status" => "fail"})
      end
    end

    context "with time and duration expectations" do
      before do
        produce_test_session_trace
      end

      it "correctly serializes start and duration in nanoseconds" do
        expect(content["start"]).to be_a(Integer)
        expect(content["start"]).to be > 0
        expect(content["duration"]).to be_a(Integer)
        expect(content["duration"]).to be > 0
      end
    end

    context "with itr correlation id" do
      let(:options) { {itr_correlation_id: "itr-correlation-id"} }

      before do
        produce_test_session_trace
      end

      it "correctly serializes itr correlation id" do
        expect(content).to include("itr_correlation_id" => "itr-correlation-id")
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
          first_test_span.clear_tag("_test.session_id")
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
          first_test_span.clear_tag("_test.module_id")
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
          first_test_span.clear_tag("_test.suite_id")
        end

        it { is_expected.not_to be_valid }
      end
    end
  end
end
