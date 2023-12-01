# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSuite do
  let(:test_suite_name) { "my.suite" }
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true, name: test_suite_name) }

  describe "#finish" do
    subject(:ci_test_suite) { described_class.new(tracer_span) }

    before { allow(Datadog::CI).to receive(:deactivate_test_suite) }

    it "deactivates the test suite" do
      ci_test_suite.finish

      expect(Datadog::CI).to have_received(:deactivate_test_suite).with(test_suite_name)
    end
  end
end
