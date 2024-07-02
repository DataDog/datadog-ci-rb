# frozen_string_literal: true

RSpec.describe Datadog::CI::TestModule do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }
  let(:test_visibility) { spy("test_visibility") }

  before { allow_any_instance_of(described_class).to receive(:test_visibility).and_return(test_visibility) }

  describe "#finish" do
    subject(:ci_test_module) { described_class.new(tracer_span) }

    it "deactivates the test module" do
      ci_test_module.finish

      expect(test_visibility).to have_received(:deactivate_test_module)
    end
  end
end
