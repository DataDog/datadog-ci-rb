# frozen_string_literal: true

RSpec.describe Datadog::CI::TestModule do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }
  let(:recorder) { spy("recorder") }

  before { allow_any_instance_of(described_class).to receive(:recorder).and_return(recorder) }

  describe "#finish" do
    subject(:ci_test_module) { described_class.new(tracer_span) }

    it "deactivates the test module" do
      ci_test_module.finish

      expect(recorder).to have_received(:deactivate_test_module)
    end
  end
end
