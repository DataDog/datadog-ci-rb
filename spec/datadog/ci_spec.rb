RSpec.describe Datadog::CI do
  context "with test visibility stubbed" do
    include_context "Telemetry spy"
    let(:test_visibility) { instance_double(Datadog::CI::TestVisibility::Component) }

    before do
      allow(Datadog::CI).to receive(:test_visibility).and_return(test_visibility)
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
        allow(test_visibility).to receive(:trace_test).with(test_name, test_suite_name, **options, &block).and_return(ci_test)
      end

      it { is_expected.to be(ci_test) }

      it_behaves_like "emits telemetry metric", :inc, "manual_api_events", 1
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
        allow(test_visibility).to receive(:trace_test).with(test_name, test_suite_name, **options).and_return(ci_test)
      end

      it { is_expected.to be(ci_test) }

      it_behaves_like "emits telemetry metric", :inc, "manual_api_events", 1
    end

    describe "::trace" do
      subject(:trace) { described_class.trace(span_name, type: type, **options, &block) }

      let(:type) { "span type" }
      let(:span_name) { "span name" }
      let(:options) { {tags: {"foo" => "bar"}} }
      let(:block) { proc {} }

      let(:ci_span) { instance_double(Datadog::CI::Span) }

      before do
        allow(test_visibility).to receive(:trace).with(span_name, type: type, **options, &block).and_return(ci_span)
      end

      it { is_expected.to be(ci_span) }

      context "when using reserved type" do
        let(:type) { Datadog::CI::Ext::AppTypes::TYPE_TEST }

        it "raises error" do
          expect { trace }.to raise_error(Datadog::CI::ReservedTypeError)
        end
      end
    end

    describe "::active_span" do
      subject(:active_span) { described_class.active_span }

      let(:type) { "span type" }

      context "when current active span has custom type" do
        let(:ci_span) { instance_double(Datadog::CI::Span, type: type) }

        before do
          allow(test_visibility).to receive(:active_span).and_return(ci_span)
        end

        it { is_expected.to be(ci_span) }
      end

      context "when current active span is a test" do
        let(:ci_span) { instance_double(Datadog::CI::Span, type: "test") }

        before do
          allow(test_visibility).to receive(:active_span).and_return(ci_span)
        end

        it { is_expected.to be_nil }
      end

      context "when no active span" do
        before do
          allow(test_visibility).to receive(:active_span).and_return(nil)
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
          allow(test_visibility).to receive(:start_test_session).with(
            service: service, tags: {}, estimated_total_tests_count: 0
          ).and_return(ci_test_session)
        end

        it { is_expected.to be(ci_test_session) }

        it_behaves_like "emits telemetry metric", :inc, "manual_api_events", 1
      end

      context "when service is not provided" do
        subject(:start_test_session) { described_class.start_test_session }

        context "when service is configured on library level" do
          before do
            allow(Datadog.configuration).to receive(:service_without_fallback).and_return("configured-service")
            allow(test_visibility).to receive(:start_test_session).with(
              service: "configured-service", tags: {}, estimated_total_tests_count: 0
            ).and_return(ci_test_session)
          end

          it { is_expected.to be(ci_test_session) }
        end

        context "when service is not configured on library level" do
          before do
            allow(Datadog.configuration).to receive(:service_without_fallback).and_return(nil)
            allow(test_visibility).to receive(:start_test_session).with(
              service: "datadog-ci-rb", tags: {}, estimated_total_tests_count: 0
            ).and_return(ci_test_session)
          end

          it { is_expected.to be(ci_test_session) }
        end
      end

      context "when total_tests_count is provided" do
        let(:total_tests_count) { 42 }
        subject(:start_test_session) { described_class.start_test_session(total_tests_count: total_tests_count) }

        before do
          allow(test_visibility).to receive(:start_test_session).with(
            service: "datadog-ci-rb", tags: {}, estimated_total_tests_count: total_tests_count
          ).and_return(ci_test_session)
        end

        it { is_expected.to be(ci_test_session) }

        it_behaves_like "emits telemetry metric", :inc, "manual_api_events", 1
      end
    end

    describe "::active_test_session" do
      subject(:active_test_session) { described_class.active_test_session }

      let(:ci_test_session) { instance_double(Datadog::CI::TestSession) }

      before do
        allow(test_visibility).to receive(:active_test_session).and_return(ci_test_session)
      end

      it { is_expected.to be(ci_test_session) }
    end

    describe "::start_test_module" do
      subject(:start_test_module) { described_class.start_test_module("my-module") }

      let(:ci_test_module) { instance_double(Datadog::CI::TestModule) }

      before do
        allow(test_visibility).to(
          receive(:start_test_module).with("my-module", service: nil, tags: {}).and_return(ci_test_module)
        )
      end

      it { is_expected.to be(ci_test_module) }

      it_behaves_like "emits telemetry metric", :inc, "manual_api_events", 1
    end

    describe "::active_test_module" do
      subject(:active_test_module) { described_class.active_test_module }

      let(:ci_test_module) { instance_double(Datadog::CI::TestModule) }

      before do
        allow(test_visibility).to receive(:active_test_module).and_return(ci_test_module)
      end

      it { is_expected.to be(ci_test_module) }
    end

    describe "::start_test_suite" do
      subject(:start_test_suite) { described_class.start_test_suite("my-suite") }

      let(:ci_test_suite) { instance_double(Datadog::CI::TestSuite) }

      before do
        allow(test_visibility).to(
          receive(:start_test_suite).with("my-suite", service: nil, tags: {}).and_return(ci_test_suite)
        )
      end

      it { is_expected.to be(ci_test_suite) }

      it_behaves_like "emits telemetry metric", :inc, "manual_api_events", 1
    end

    describe "::active_test_suite" do
      let(:test_suite_name) { "my-suite" }
      subject(:active_test_suite) { described_class.active_test_suite(test_suite_name) }

      let(:ci_test_suite) { instance_double(Datadog::CI::TestSuite) }

      before do
        allow(test_visibility).to receive(:active_test_suite).with(test_suite_name).and_return(ci_test_suite)
      end

      it { is_expected.to be(ci_test_suite) }
    end
  end

  context "integration testing the manual API" do
    context "when CI mode is disabled" do
      include_context "CI mode activated" do
        let(:ci_enabled) { false }
      end

      before do
        produce_test_session_trace(with_http_span: true)
      end

      it "doesn't record spans via Datadog::CI interface" do
        expect(spans).to have(1).item # http span only
      end
    end

    context "when CI mode is enabled" do
      context "when test suite level visibility is enabled" do
        include_context "CI mode activated" do
          let(:ci_enabled) { true }
        end

        before do
          produce_test_session_trace(with_http_span: true)
        end

        it "records test suite level spans" do
          expect(spans).to have(5).items # session + module + suite + test + http span
          expect(test_session_span).not_to be_nil
        end
      end

      context "when test suite level visibility is disabled" do
        include_context "CI mode activated" do
          let(:force_test_level_visibility) { true }
          let(:ci_enabled) { true }
        end

        before do
          produce_test_session_trace(with_http_span: true)
        end

        it "does not record test suite level spans" do
          expect(spans).to have(2).items # test + http span
          expect(test_session_span).to be_nil
        end
      end
    end
  end
end
