# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSuite do
  let(:test_suite_name) { "my.suite" }
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true, name: test_suite_name) }
  let(:recorder) { spy("recorder") }

  before { allow_any_instance_of(described_class).to receive(:recorder).and_return(recorder) }

  describe "#finish" do
    subject(:ci_test_suite) { described_class.new(tracer_span) }

    it "deactivates the test suite" do
      ci_test_suite.finish

      expect(recorder).to have_received(:deactivate_test_suite).with(test_suite_name)
    end
  end
end
