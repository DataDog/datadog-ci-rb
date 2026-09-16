# frozen_string_literal: true

require_relative "../../../../../lib/datadog/ci/contrib/knapsack/runner"

RSpec.describe Datadog::CI::Contrib::Knapsack::Runner do
  describe "#knapsack__run_specs" do
    let(:test_session) { instance_double(Datadog::CI::TestSession) }
    let(:test_module) { instance_double(Datadog::CI::TestModule) }
    let(:test_tracing_component) { instance_double(Datadog::CI::TestTracing::Component) }
    let(:interruption) { Class.new(StandardError) }
    let(:runner) do
      interruption_error = interruption
      runner_class = Class.new do
        define_method(:knapsack__run_specs) do |*|
          raise interruption_error, "test run interrupted"
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
    end

    it "marks and finishes the test run before propagating an interruption" do
      expect(test_module).to receive(:failed!).ordered
      expect(test_session).to receive(:failed!).ordered
      expect(test_module).to receive(:finish).ordered
      expect(test_session).to receive(:finish).ordered

      expect { runner.knapsack__run_specs }.to raise_error(interruption, "test run interrupted")
    end
  end
end
