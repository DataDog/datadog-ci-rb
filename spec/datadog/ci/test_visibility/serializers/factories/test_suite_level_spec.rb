require_relative "../../../../../../lib/datadog/ci/test_visibility/serializers/factories/test_suite_level"
require_relative "../../../../../../lib/datadog/ci/test_visibility/serializers/test_v2"
require_relative "../../../../../../lib/datadog/ci/test_visibility/serializers/test_session"
require_relative "../../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers::Factories::TestSuiteLevel do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  before do
    produce_test_session_trace(with_http_span: true)
  end

  subject { described_class.serializer(trace, ci_span) }

  describe ".convert_trace_to_serializable_events" do
    context "with a session span" do
      let(:ci_span) { test_session_span }
      it { is_expected.to be_kind_of(Datadog::CI::TestVisibility::Serializers::TestSession) }
    end

    context "with a test span" do
      let(:ci_span) { first_test_span }
      it { is_expected.to be_kind_of(Datadog::CI::TestVisibility::Serializers::TestV2) }
    end

    context "with a http request span" do
      let(:ci_span) { first_other_span }
      it { is_expected.to be_kind_of(Datadog::CI::TestVisibility::Serializers::Span) }
    end
  end
end
