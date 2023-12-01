# frozen_string_literal: true

RSpec.describe Datadog::CI::TestModule do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }

  describe "#finish" do
    subject(:ci_test_module) { described_class.new(tracer_span) }

    before { allow(Datadog::CI).to receive(:deactivate_test_module) }

    it "deactivates the test module" do
      ci_test_module.finish

      expect(Datadog::CI).to have_received(:deactivate_test_module)
    end
  end
end
