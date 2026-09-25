# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/knapsack/runner"

RSpec.describe Datadog::CI::Contrib::Knapsack::Runner do
  describe "#knapsack__run_specs" do
    let(:test_session) { instance_double(Datadog::CI::TestSession) }
    let(:test_module) { instance_double(Datadog::CI::TestModule) }
    let(:test_tracing_component) { instance_double(Datadog::CI::TestTracing::Component) }
    let(:interruption) { StandardError.new("test run interrupted") }
    let(:run_error) { interruption }
    let(:run_result) { nil }
    let(:runner) do
      error = run_error
      result = run_result
      runner_class = Class.new do
        define_method(:knapsack__run_specs) do |*|
          raise error if error

          result
        end

        include Datadog::CI::Contrib::Knapsack::Runner
      end

      runner_class.new.tap do |instance|
        allow(instance).to receive(:datadog_configuration).and_return(
          enabled: true,
          dry_run_enabled: false,
          service_name: nil
        )
        allow(instance).to receive(:datadog_integration).and_return(double(version: Gem::Version.new("1.0.0")))
        allow(instance).to receive(:test_tracing_component).and_return(test_tracing_component)
      end
    end

    before do
      allow(test_tracing_component).to receive(:start_test_session).and_return(test_session)
      allow(test_tracing_component).to receive(:start_test_module).and_return(test_module)
      allow(test_tracing_component).to receive(:any_tests_started?).and_return(true)
    end

    it "marks and finishes the test run before propagating an interruption" do
      expect(test_module).to receive(:failed!).ordered
      expect(test_session).to receive(:failed!).ordered
      expect(test_module).to receive(:finish).ordered
      expect(test_session).to receive(:finish).ordered

      expect { runner.knapsack__run_specs }.to raise_error { |error| expect(error).to equal(interruption) }
    end

    shared_examples "tolerates cleanup failures" do
      [:test_module, :test_session].each do |span_name|
        [:status, :finish].each do |operation|
          it "preserves the run outcome and attempts all cleanup when #{span_name} #{operation} raises" do
            status_method = (run_result == 0) ? :passed! : :failed!
            failing_method = (operation == :status) ? status_method : :finish
            cleanup_error = RuntimeError.new("cleanup failed")

            [test_module, test_session].each do |span|
              [status_method, :finish].each do |method|
                expect(span).to receive(method) do
                  raise cleanup_error if span.equal?(public_send(span_name)) && method == failing_method
                end
              end
            end
            expect(Datadog.logger).to receive(:warn).with(/Knapsack.*RuntimeError: cleanup failed/)

            if run_error
              expect { runner.knapsack__run_specs }.to raise_error { |error| expect(error).to equal(run_error) }
            else
              expect(runner.knapsack__run_specs).to eq(run_result)
            end
          end
        end
      end
    end

    context "when the run is interrupted" do
      include_examples "tolerates cleanup failures"
    end

    context "when the run passes" do
      let(:run_error) { nil }
      let(:run_result) { 0 }

      include_examples "tolerates cleanup failures"
    end

    context "when the run fails" do
      let(:run_error) { nil }
      let(:run_result) { 1 }

      include_examples "tolerates cleanup failures"
    end

    context "when no tests start" do
      let(:run_error) { nil }

      before do
        allow(test_tracing_component).to receive(:any_tests_started?).and_return(false)
      end

      context "when the run succeeds" do
        let(:run_result) { 0 }

        it "skips and finishes the parent events" do
          [test_module, test_session].each do |span|
            expect(span).to receive(:skipped!).with(reason: "No tests were executed")
            expect(span).to receive(:set_tag).with(Datadog::CI::Ext::Test::TAG_SESSION_EMPTY_REASON, "zero_tests")
            expect(span).to receive(:finish)
          end

          expect(runner.knapsack__run_specs).to eq(0)
        end
      end

      context "when the run fails" do
        let(:run_result) { 1 }

        include_examples "tolerates cleanup failures"
      end
    end
  end
end
