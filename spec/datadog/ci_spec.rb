RSpec.describe Datadog::CI do
  describe "::trace_test" do
    subject(:trace_test) { described_class.trace_test(test_name, **options, &block) }

    let(:test_name) { "test name" }
    let(:options) do
      {
        service_name: "my-serivce",
        operation_name: "rspec.example",
        tags: {"foo" => "bar"}
      }
    end
    let(:block) { proc {} }

    let(:recorder) { instance_double(Datadog::CI::Recorder) }
    let(:ci_test) { instance_double(Datadog::CI::Span) }

    before do
      allow(Datadog::CI).to receive(:recorder).and_return(recorder)

      allow(recorder).to receive(:trace_test).with(test_name, **options, &block).and_return(ci_test)
    end

    it { is_expected.to be(ci_test) }
  end

  describe "::trace" do
    subject(:trace) { described_class.trace(span_type, span_name, **options, &block) }

    let(:span_type) { "span type" }
    let(:span_name) { "span name" }
    let(:options) { {tags: {"foo" => "bar"}} }
    let(:block) { proc {} }

    let(:recorder) { instance_double(Datadog::CI::Recorder) }
    let(:ci_span) { instance_double(Datadog::CI::Span) }

    before do
      allow(Datadog::CI).to receive(:recorder).and_return(recorder)

      allow(recorder).to receive(:trace).with(span_type, span_name, **options, &block).and_return(ci_span)
    end

    it { is_expected.to be(ci_span) }
  end
end
