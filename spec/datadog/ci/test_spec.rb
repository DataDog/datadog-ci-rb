# frozen_string_literal: true

RSpec.describe Datadog::CI::Test do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }

  describe "#name" do
    subject(:name) { ci_test.name }
    let(:ci_test) { described_class.new(tracer_span) }

    before { allow(ci_test).to receive(:get_tag).with(Datadog::CI::Ext::Test::TAG_NAME).and_return("test name") }

    it { is_expected.to eq("test name") }
  end

  describe "#finish" do
    subject(:ci_test) { described_class.new(tracer_span) }

    before { allow(Datadog::CI).to receive(:deactivate_test) }

    it "deactivates the test" do
      ci_test.finish
      expect(Datadog::CI).to have_received(:deactivate_test).with(ci_test)
    end
  end
end
