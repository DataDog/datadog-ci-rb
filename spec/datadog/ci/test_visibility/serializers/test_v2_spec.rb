require_relative "../../../../../lib/datadog/ci/test_visibility/serializers/test_v2"
require_relative "../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers::TestV2 do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "Test visibility event serialized" do
    subject { described_class.new(trace_for_span(first_test_span), first_test_span) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_session_trace
      end

      it "serializes test event to messagepack" do
        expect_event_header(version: 2)

        expect(content).to include(
          {
            "trace_id" => trace.id,
            "span_id" => first_test_span.id,
            "name" => "rspec.test",
            "service" => "rspec-test-suite",
            "type" => "test",
            "resource" => "calculator_tests.test_add.run.0",
            "test_session_id" => test_session_span.id.to_s
          }
        )

        expect(meta).to include(
          {
            "test.name" => "test_add.run.0",
            "test.framework" => "rspec",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test",
            "test_owner" => "my_team"
          }
        )
        expect(meta["_test.session_id"]).to be_nil

        expect(metrics).to eq({"memory_allocations" => 16})
      end
    end

    context "trace several tests executions with Recorder" do
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
              "test_session_id" => test_session_span.id.to_s
            }
          )
        end
      end

      it "all tests have the same trace_id" do
        unique_trace_ids = msgpack_jsons.map { |msgpack_json| msgpack_json["content"]["trace_id"] }.uniq
        expect(unique_trace_ids.size).to eq(1)
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
      let(:start_time) { Time.now }
      let(:duration_seconds) { 3 }

      before do
        produce_test_session_trace(start_time: start_time, duration_seconds: duration_seconds)
      end

      it "correctly serializes start and duration in nanoseconds" do
        expect(content).to include({
          "start" => start_time.to_i * 1_000_000_000 + start_time.nsec,
          "duration" => 3 * 1_000_000_000
        })
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
          first_test_span.clear_tag("_test.session_id")
        end

        it "returns false" do
          expect(subject.valid?).to eq(false)
        end
      end
    end
  end
end
