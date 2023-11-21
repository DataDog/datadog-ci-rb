RSpec.describe Datadog::CI do
  let(:recorder) { instance_double(Datadog::CI::Recorder) }

  before do
    allow(Datadog::CI).to receive(:recorder).and_return(recorder)
  end

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

    let(:ci_test) { instance_double(Datadog::CI::Test) }

    before do
      allow(recorder).to receive(:trace_test).with(test_name, **options, &block).and_return(ci_test)
    end

    it { is_expected.to be(ci_test) }
  end

  describe "::start_test" do
    subject(:start_test) { described_class.start_test(test_name, **options) }

    let(:test_name) { "test name" }
    let(:options) do
      {
        service_name: "my-serivce",
        operation_name: "rspec.example",
        tags: {"foo" => "bar"}
      }
    end

    let(:ci_test) { instance_double(Datadog::CI::Test) }

    before do
      allow(recorder).to receive(:trace_test).with(test_name, **options).and_return(ci_test)
    end

    it { is_expected.to be(ci_test) }
  end

  describe "::trace" do
    subject(:trace) { described_class.trace(span_type, span_name, **options, &block) }

    let(:span_type) { "span type" }
    let(:span_name) { "span name" }
    let(:options) { {tags: {"foo" => "bar"}} }
    let(:block) { proc {} }

    let(:ci_span) { instance_double(Datadog::CI::Span) }

    before do
      allow(recorder).to receive(:trace).with(span_type, span_name, **options, &block).and_return(ci_span)
    end

    it { is_expected.to be(ci_span) }
  end

  describe "::active_span" do
    subject(:active_span) { described_class.active_span(span_type) }

    let(:span_type) { "span type" }

    context "when span type matches current active span" do
      let(:ci_span) { instance_double(Datadog::CI::Span, span_type: span_type) }

      before do
        allow(recorder).to receive(:active_span).and_return(ci_span)
      end

      it { is_expected.to be(ci_span) }
    end

    context "when span type does not match current active span" do
      let(:ci_span) { instance_double(Datadog::CI::Span, span_type: "other span type") }

      before do
        allow(recorder).to receive(:active_span).and_return(ci_span)
      end

      it { is_expected.to be_nil }
    end

    context "when no active span" do
      before do
        allow(recorder).to receive(:active_span).and_return(nil)
      end

      it { is_expected.to be_nil }
    end
  end

  describe "::start_test_session" do
    subject(:start_test_session) { described_class.start_test_session }

    let(:ci_test_session) { instance_double(Datadog::CI::TestSession) }

    before do
      allow(recorder).to receive(:start_test_session).and_return(ci_test_session)
    end

    it { is_expected.to be(ci_test_session) }
  end

  describe "::active_test_session" do
    subject(:active_test_session) { described_class.active_test_session }

    let(:ci_test_session) { instance_double(Datadog::CI::TestSession) }

    before do
      allow(recorder).to receive(:active_test_session).and_return(ci_test_session)
    end

    it { is_expected.to be(ci_test_session) }
  end

  describe "::deactivate_test_session" do
    subject(:deactivate_test_session) { described_class.deactivate_test_session }

    before do
      allow(recorder).to receive(:deactivate_test_session)
    end

    it { is_expected.to be_nil }
  end
end
