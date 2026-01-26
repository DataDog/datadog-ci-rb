require_relative "../../../../../../lib/datadog/ci/test_tracing/serializers/factories/test_suite_level"
require_relative "../../../../../../lib/datadog/ci/test_tracing/serializers/test_v2"
require_relative "../../../../../../lib/datadog/ci/test_tracing/serializers/test_session"
require_relative "../../../../../../lib/datadog/ci/test_tracing/component"

RSpec.describe Datadog::CI::TestTracing::Serializers::Factories::TestSuiteLevel do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  before do
    produce_test_session_trace(with_http_span: true)
  end

  context "without options" do
    subject { described_class.serializer(trace_for_span(ci_span), ci_span) }

    describe ".convert_trace_to_serializable_events" do
      context "with a session span" do
        let(:ci_span) { test_session_span }
        it { is_expected.to be_kind_of(Datadog::CI::TestTracing::Serializers::TestSession) }
      end

      context "with a module span" do
        let(:ci_span) { test_module_span }
        it { is_expected.to be_kind_of(Datadog::CI::TestTracing::Serializers::TestModule) }
      end

      context "with a suite span" do
        let(:ci_span) { first_test_suite_span }
        it { is_expected.to be_kind_of(Datadog::CI::TestTracing::Serializers::TestSuite) }
      end

      context "with a test span" do
        let(:ci_span) { first_test_span }
        it { is_expected.to be_kind_of(Datadog::CI::TestTracing::Serializers::TestV2) }
      end

      context "with a http request span" do
        let(:ci_span) { first_custom_span }
        it { is_expected.to be_kind_of(Datadog::CI::TestTracing::Serializers::Span) }
      end
    end
  end

  context "with options" do
    let(:ci_span) { first_test_span }
    subject { described_class.serializer(trace_for_span(ci_span), ci_span, options: {custom: "option"}) }

    describe ".serializer" do
      it "passes options to the serializer" do
        expect(subject.options).to eq({custom: "option"})
      end
    end
  end
end
