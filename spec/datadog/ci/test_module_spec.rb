# frozen_string_literal: true

RSpec.describe Datadog::CI::TestModule do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }
  let(:test_tracing) { spy("test_tracing") }

  before { allow_any_instance_of(described_class).to receive(:test_tracing).and_return(test_tracing) }

  describe "#finish" do
    subject(:ci_test_module) { described_class.new(tracer_span) }

    it "deactivates the test module" do
      ci_test_module.finish

      expect(test_tracing).to have_received(:deactivate_test_module)
    end
  end
end
