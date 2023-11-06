RSpec.describe Datadog::CI::Recorder do
  let(:trace_op) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:service) { "service" }
  let(:operation_name) { "span name" }

  subject(:recorder) { described_class.new }

  before do
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace_op)
    allow(trace_op).to receive(:origin=)
  end

  shared_examples_for "internal tracing context" do
    it do
      expect(Datadog::Tracing::Contrib::Analytics)
        .to have_received(:set_measured)
        .with(span_op)
    end

    it do
      expect(trace_op)
        .to have_received(:origin=)
        .with(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  describe "#trace_test" do
    let(:tags) { {} }
    let(:test_name) { "test name" }

    let(:expected_tags) do
      tags
        .merge(Datadog::CI::Ext::Environment.tags(ENV))
        .merge({Datadog::CI::Ext::Test::TAG_NAME => test_name})
    end

    context "when given a block" do
      subject(:trace) do
        recorder.trace_test(
          test_name,
          service_name: service,
          operation_name: operation_name,
          tags: tags,
          &block
        )
      end

      let(:span_op) { Datadog::Tracing::SpanOperation.new(operation_name) }
      let(:ci_test) { instance_double(Datadog::CI::Span) }
      let(:block) { proc { |s| block_spy.call(s) } }
      let(:block_result) { double("result") }
      let(:block_spy) { spy("block") }

      before do
        allow(block_spy).to receive(:call).and_return(block_result)

        allow(Datadog::Tracing)
          .to receive(:trace) do |trace_span_name, trace_span_options, &trace_block|
            expect(trace_span_name).to be(operation_name)
            expect(trace_span_options).to eq(
              {
                span_type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
                resource: test_name,
                service: service
              }
            )
            trace_block.call(span_op, trace_op)
          end

        allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_test)

        trace
      end

      it_behaves_like "internal tracing context"
      it { expect(block_spy).to have_received(:call).with(ci_test) }
      it { is_expected.to be(block_result) }
    end

    context "when not given a block" do
      subject(:trace) do
        recorder.trace_test(
          test_name,
          service_name: service,
          operation_name: operation_name,
          tags: tags
        )
      end
      let(:span_op) { Datadog::Tracing::SpanOperation.new(operation_name) }
      let(:ci_test) { instance_double(Datadog::CI::Span) }

      before do
        allow(Datadog::Tracing)
          .to receive(:trace)
          .with(
            operation_name,
            {
              span_type: Datadog::CI::Ext::AppTypes::TYPE_TEST,
              resource: test_name,
              service: service
            }
          )
          .and_return(span_op)

        allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_test)

        trace
      end

      it_behaves_like "internal tracing context"
      it { is_expected.to be(ci_test) }
    end
  end

  describe "#trace" do
    let(:tags) { {"my_tag" => "my_value"} }
    let(:span_type) { "step" }
    let(:span_name) { "span name" }

    let(:expected_tags) { tags }

    context "when given a block" do
      subject(:trace) do
        recorder.trace(
          span_type,
          span_name,
          tags: tags,
          &block
        )
      end

      let(:span_op) { Datadog::Tracing::SpanOperation.new(span_name) }
      let(:ci_span) { instance_double(Datadog::CI::Span) }
      let(:block) { proc { |s| block_spy.call(s) } }
      let(:block_result) { double("result") }
      let(:block_spy) { spy("block") }

      before do
        allow(block_spy).to receive(:call).and_return(block_result)

        allow(Datadog::Tracing)
          .to receive(:trace) do |trace_span_name, trace_span_options, &trace_block|
            expect(trace_span_name).to be(span_name)
            expect(trace_span_options).to eq(
              {
                span_type: span_type,
                resource: span_name
              }
            )
            trace_block.call(span_op, trace_op)
          end

        allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_span)

        trace
      end

      it_behaves_like "internal tracing context"
      it { expect(block_spy).to have_received(:call).with(ci_span) }
      it { is_expected.to be(block_result) }
    end

    context "when not given a block" do
      subject(:trace) do
        recorder.trace(
          span_type,
          span_name,
          tags: tags
        )
      end

      let(:span_op) { Datadog::Tracing::SpanOperation.new(span_name) }
      let(:ci_span) { instance_double(Datadog::CI::Span) }

      before do
        allow(Datadog::Tracing)
          .to receive(:trace)
          .with(
            span_name,
            {
              span_type: span_type,
              resource: span_name
            }
          )
          .and_return(span_op)

        allow(Datadog::Tracing::Contrib::Analytics).to receive(:set_measured)
        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_span)

        trace
      end

      it_behaves_like "internal tracing context"
      it { is_expected.to be(ci_span) }
    end
  end
end
