require_relative "../../../../../lib/datadog/ci/test_visibility/serializers/test_v1"
require_relative "../../../../../lib/datadog/ci/test_visibility/component"

RSpec.describe Datadog::CI::TestVisibility::Serializers::TestV1 do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  include_context "msgpack serializer" do
    subject { described_class.new(trace_for_span(span), span) }
  end

  describe "#to_msgpack" do
    context "traced a single test execution with test visibility" do
      before do
        produce_test_trace
      end

      it "serializes test event to messagepack" do
        expect_event_header

        expect(content).to include(
          {
            "trace_id" => span.trace_id,
            "span_id" => span.id,
            "name" => "rspec.test",
            "service" => "rspec-test-suite",
            "type" => "test",
            "resource" => "calculator_tests.test_add"
          }
        )

        expect(meta).to include(
          {
            "test.framework" => "rspec",
            "test.status" => "pass",
            "_dd.origin" => "ciapp-test",
            "test_owner" => "my_team"
          }
        )
        expect(metrics).to eq(
          {"_dd.top_level" => 1.0, "memory_allocations" => 16, "_dd.host.vcpu_count" => Etc.nprocessors}
        )
      end
    end

    context "trace a failed test" do
      before do
        produce_test_trace(result: "FAILED", exception: StandardError.new("1 + 2 are not equal to 5"))
      end

      it "has error" do
        expect_event_header

        expect(content).to include({"error" => 1})
        expect(meta).to include({"test.status" => "fail"})
      end
    end

    context "with time and duration expectations" do
      before do
        produce_test_trace
      end

      it "serializes start and duration" do
        expect(content["start"]).to be_a(Integer)
        expect(content["start"]).to be > 0
        expect(content["duration"]).to be_a(Integer)
        expect(content["duration"]).to be > 0
      end
    end
  end

  describe "#valid?" do
    context "duration" do
      before do
        produce_test_trace
        span.duration = duration
      end

      context "when positive number" do
        let(:duration) { 42 }

        it { is_expected.to be_valid }
      end

      context "when negative number" do
        let(:duration) { -1 }

        it { is_expected.not_to be_valid }

        it "includes validation error" do
          subject.valid?
          expect(subject.validation_errors["duration"]).to include("must be greater than or equal to 0")
        end
      end

      context "when too big" do
        let(:duration) { Datadog::CI::TestVisibility::Serializers::Base::MAXIMUM_DURATION_NANO + 1 }

        it { is_expected.not_to be_valid }

        it "includes validation error" do
          subject.valid?
          expect(subject.validation_errors["duration"]).to include("must be less than or equal to 9223372036854775807")
        end
      end
    end

    context "start" do
      before do
        produce_test_trace
        span.start_time = start_time
      end

      context "when now" do
        let(:start_time) { Time.now }

        it { is_expected.to be_valid }
      end

      context "when far in the past" do
        let(:start_time) { Time.at(0) }

        it { is_expected.not_to be_valid }

        it "has validation error" do
          subject.valid?
          expect(subject.validation_errors["start"]).to include("must be greater than or equal to 946684800000000000")
        end
      end
    end
  end
end
