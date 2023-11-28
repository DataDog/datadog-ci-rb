# frozen_string_literal: true

RSpec.describe Datadog::CI::TestSession do
  let(:tracer_span) { instance_double(Datadog::Tracing::SpanOperation, finish: true) }

  describe "#finish" do
    subject(:ci_test_session) { described_class.new(tracer_span) }

    before { allow(Datadog::CI).to receive(:deactivate_test_session) }

    it "deactivates the test session" do
      ci_test_session.finish

      expect(Datadog::CI).to have_received(:deactivate_test_session)
    end
  end

  describe "#inheritable_tags" do
    subject(:inheritable_tags) { ci_test_session.inheritable_tags }

    let(:ci_test_session) { described_class.new(tracer_span) }

    before do
      Datadog::CI::Ext::Test::INHERITABLE_TAGS.each do |tag|
        allow(tracer_span).to receive(:get_tag).with(tag).and_return("value for #{tag}")
      end
    end

    it "returns a hash of inheritable tags" do
      is_expected.to eq(
        Datadog::CI::Ext::Test::INHERITABLE_TAGS.each_with_object({}) do |tag, memo|
          memo[tag] = "value for #{tag}"
        end
      )
    end
  end
end
