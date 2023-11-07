RSpec.describe Datadog::CI::Recorder do
  let(:trace_op) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:service) { "service" }
  let(:operation_name) { "span name" }
  let(:test_name) { "test name" }
  let(:tags) { {} }
  let(:environment_tags) { Datadog::CI::Ext::Environment.tags(ENV) }

  subject(:recorder) { described_class.new }

  before do
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace_op)
    allow(trace_op).to receive(:origin=)
  end

  shared_examples_for "internal tracing context" do
    it do
      expect(trace_op)
        .to have_received(:origin=)
        .with(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end
  end

  describe "#trace_test" do
    def expect_initialized_test
      allow(Datadog::CI::Test).to receive(:new).with(span_op).and_return(ci_test)
      expect(ci_test).to receive(:set_default_tags)
      expect(ci_test).to receive(:set_environment_runtime_tags)
      expect(ci_test).to receive(:set_tags).with(tags)
      expect(ci_test).to receive(:set_tags).with(environment_tags)
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
      let(:ci_test) { instance_double(Datadog::CI::Test) }
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

            expect_initialized_test

            trace_block.call(span_op, trace_op)
          end

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
      let(:ci_test) { instance_double(Datadog::CI::Test) }

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

        expect_initialized_test

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

        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_span)

        trace
      end

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

        allow(Datadog::CI::Span).to receive(:new).with(span_op, expected_tags).and_return(ci_span)

        trace
      end

      it { is_expected.to be(ci_span) }
    end
  end

  describe "#active_test" do
    subject(:active_test) { recorder.active_test }

    let(:ci_test) do
      recorder.trace_test(
        test_name,
        service_name: service,
        operation_name: operation_name,
        tags: tags
      )
    end

    before { ci_test }

    it { is_expected.to be(ci_test) }
  end

  describe "#deactivate_test" do
    subject(:deactivate_test) { recorder.deactivate_test(ci_test) }

    let(:ci_test) do
      recorder.trace_test(
        test_name,
        service_name: service,
        operation_name: operation_name,
        tags: tags
      )
    end

    before { deactivate_test }

    it { expect(recorder.active_test).to be_nil }
  end

  describe "#active_span" do
    subject(:active_span) { recorder.active_span }

    context "when there is active span in tracing context" do
      let(:span_op) { Datadog::Tracing::SpanOperation.new(operation_name) }
      let(:ci_span) { instance_double(Datadog::CI::Span) }

      before do
        allow(Datadog::Tracing).to receive(:active_span).and_return(span_op)
        allow(Datadog::CI::Span).to receive(:new).with(span_op).and_return(ci_span)
      end

      it { is_expected.to be(ci_span) }
    end

    context "when there is no active span in tracing context" do
      before { allow(Datadog::Tracing).to receive(:active_span).and_return(nil) }

      it { is_expected.to be_nil }
    end
  end
end
