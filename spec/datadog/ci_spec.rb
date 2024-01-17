RSpec.describe Datadog::CI do
  context "with recorder stubbed" do
    let(:recorder) { instance_double(Datadog::CI::TestVisibility::Recorder) }

    before do
      allow(Datadog::CI).to receive(:recorder).and_return(recorder)
    end

    describe "::trace_test" do
      subject(:trace_test) { described_class.trace_test(test_name, test_suite_name, **options, &block) }

      let(:test_name) { "test name" }
      let(:test_suite_name) { "test suite name" }
      let(:options) do
        {
          service: "my-serivce",
          tags: {"foo" => "bar"}
        }
      end
      let(:block) { proc {} }

      let(:ci_test) { instance_double(Datadog::CI::Test) }

      before do
        allow(recorder).to receive(:trace_test).with(test_name, test_suite_name, **options, &block).and_return(ci_test)
      end

      it { is_expected.to be(ci_test) }
    end

    describe "::start_test" do
      subject(:start_test) { described_class.start_test(test_name, test_suite_name, **options) }

      let(:test_name) { "test name" }
      let(:test_suite_name) { "test suite name" }
      let(:options) do
        {
          service: "my-serivce",
          tags: {"foo" => "bar"}
        }
      end

      let(:ci_test) { instance_double(Datadog::CI::Test) }

      before do
        allow(recorder).to receive(:trace_test).with(test_name, test_suite_name, **options).and_return(ci_test)
      end

      it { is_expected.to be(ci_test) }
    end

    describe "::trace" do
      subject(:trace) { described_class.trace(span_name, type: type, **options, &block) }

      let(:type) { "span type" }
      let(:span_name) { "span name" }
      let(:options) { {tags: {"foo" => "bar"}} }
      let(:block) { proc {} }

      let(:ci_span) { instance_double(Datadog::CI::Span) }

      before do
        allow(recorder).to receive(:trace).with(span_name, type: type, **options, &block).and_return(ci_span)
      end

      it { is_expected.to be(ci_span) }
    end

    describe "::active_span" do
      subject(:active_span) { described_class.active_span }

      let(:type) { "span type" }

      context "when current active span has custom type" do
        let(:ci_span) { instance_double(Datadog::CI::Span, type: type) }

        before do
          allow(recorder).to receive(:active_span).and_return(ci_span)
        end

        it { is_expected.to be(ci_span) }
      end

      context "when current active span is a test" do
        let(:ci_span) { instance_double(Datadog::CI::Span, type: "test") }

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
      let(:ci_test_session) { instance_double(Datadog::CI::TestSession) }

      context "when service is provided" do
        let(:service) { "my-service" }
        subject(:start_test_session) { described_class.start_test_session(service: service) }

        before do
          allow(recorder).to receive(:start_test_session).with(service: service, tags: {}).and_return(ci_test_session)
        end

        it { is_expected.to be(ci_test_session) }
      end

      context "when service is not provided" do
        subject(:start_test_session) { described_class.start_test_session }

        context "when service is configured on library level" do
          before do
            allow(Datadog.configuration).to receive(:service_without_fallback).and_return("configured-service")
            allow(recorder).to receive(:start_test_session).with(
              service: "configured-service", tags: {}
            ).and_return(ci_test_session)
          end

          it { is_expected.to be(ci_test_session) }
        end
      end
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

    describe "::start_test_module" do
      subject(:start_test_module) { described_class.start_test_module("my-module") }

      let(:ci_test_module) { instance_double(Datadog::CI::TestModule) }

      before do
        allow(recorder).to(
          receive(:start_test_module).with("my-module", service: nil, tags: {}).and_return(ci_test_module)
        )
      end

      it { is_expected.to be(ci_test_module) }
    end

    describe "::active_test_module" do
      subject(:active_test_module) { described_class.active_test_module }

      let(:ci_test_module) { instance_double(Datadog::CI::TestModule) }

      before do
        allow(recorder).to receive(:active_test_module).and_return(ci_test_module)
      end

      it { is_expected.to be(ci_test_module) }
    end

    describe "::deactivate_test_module" do
      subject(:deactivate_test_module) { described_class.deactivate_test_module }

      before do
        allow(recorder).to receive(:deactivate_test_module)
      end

      it { is_expected.to be_nil }
    end

    describe "::start_test_suite" do
      subject(:start_test_suite) { described_class.start_test_suite("my-suite") }

      let(:ci_test_suite) { instance_double(Datadog::CI::TestSuite) }

      before do
        allow(recorder).to(
          receive(:start_test_suite).with("my-suite", service: nil, tags: {}).and_return(ci_test_suite)
        )
      end

      it { is_expected.to be(ci_test_suite) }
    end

    describe "::active_test_suite" do
      let(:test_suite_name) { "my-suite" }
      subject(:active_test_suite) { described_class.active_test_suite(test_suite_name) }

      let(:ci_test_suite) { instance_double(Datadog::CI::TestSuite) }

      before do
        allow(recorder).to receive(:active_test_suite).with(test_suite_name).and_return(ci_test_suite)
      end

      it { is_expected.to be(ci_test_suite) }
    end

    describe "::deactivate_test_suite" do
      let(:test_suite_name) { "my-suite" }
      subject(:deactivate_test_suite) { described_class.deactivate_test_suite(test_suite_name) }

      before do
        allow(recorder).to receive(:deactivate_test_suite).with(test_suite_name)
      end

      it { is_expected.to be_nil }
    end
  end

  context "integration testing the manual API" do
    context "when CI mode is disabled" do
      include_context "CI mode activated" do
        let(:experimental_test_suite_level_visibility_enabled) { false }
        let(:ci_enabled) { false }
      end

      before do
        produce_test_session_trace(with_http_span: true)
      end

      it "doesn't record spans via Datadog::CI interface" do
        expect(spans.count).to eq(1) # http span only
      end
    end

    context "when CI mode is enabled" do
      context "when test suite level visibility is enabled" do
        include_context "CI mode activated" do
          let(:experimental_test_suite_level_visibility_enabled) { true }
          let(:ci_enabled) { true }
        end

        before do
          produce_test_session_trace(with_http_span: true)
        end

        it "records test suite level spans" do
          expect(spans.count).to eq(5) # session + module + suite + test + http span
          expect(test_session_span).not_to be_nil
        end
      end

      context "when test suite level visibility is disabled" do
        include_context "CI mode activated" do
          let(:experimental_test_suite_level_visibility_enabled) { false }
          let(:ci_enabled) { true }
        end

        before do
          produce_test_session_trace(with_http_span: true)
        end

        it "does not record test suite level spans" do
          expect(spans.count).to eq(2) # test + http span
          expect(test_session_span).to be_nil
        end
      end
    end
  end
end
