require_relative "../../../../../../lib/datadog/ci/test_visibility/serializers/factories/test_level"
require_relative "../../../../../../lib/datadog/ci/test_visibility/serializers/test_v1"
require_relative "../../../../../../lib/datadog/ci/recorder"

RSpec.describe Datadog::CI::TestVisibility::Serializers::Factories::TestLevel do
  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  subject { described_class.serializer(trace_for_span(span), span) }

  describe ".convert_trace_to_serializable_events" do
    context "traced a single test execution with Recorder" do
      before do
        produce_test_trace
      end

      it { is_expected.to be_kind_of(Datadog::CI::TestVisibility::Serializers::TestV1) }
    end
  end
end
