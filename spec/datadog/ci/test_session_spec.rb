# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSession do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }

  describe "#finish" do
    subject(:ci_test_session) { described_class.new(tracer_span) }

    before { allow(Datadog::CI).to receive(:deactivate_test_session) }

    it "deactivates the test" do
      ci_test_session.finish

      expect(Datadog::CI).to have_received(:deactivate_test_session)
    end
  end
end
