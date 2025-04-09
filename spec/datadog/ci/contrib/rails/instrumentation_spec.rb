require "logger"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

RSpec.describe "ActiveSupport::TestCase instrumentation" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:integration_options) { {service_name: "ltest"} }

    let(:agentless_mode_enabled) { true }
    let(:agentless_logs_enabled) { true }
    let(:api_key) { "dd-api-key" }
  end

  before do
    ::Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(File.new(File::NULL, "w")))
  end

  context "when mixin used" do
    before do
      Minitest::Runnable.reset
      require_relative "test/test_calculator"
      Minitest.run([])
    end

    it "instruments this test session with agentless logs support" do
      # test session and module traced
      expect(test_session_span).not_to be_nil
      expect(test_module_span).not_to be_nil

      expect([test_session_span, test_module_span]).to all have_pass_status

      expect(test_suite_spans).to have(1).items
      expect(test_suite_spans).to have_tag_values_no_order(:status, ["pass"])
      expect(test_suite_spans).to have_tag_values_no_order(
        :suite,
        [
          "CalculatorTest at spec/datadog/ci/contrib/rails/test/test_calculator.rb"
        ]
      )

      # there is test span for every test case
      expect(test_spans).to have(3).items

      expect(test_spans).to have_tag_values_no_order(
        :name,
        [
          "test_adds_two_numbers",
          "test_should_divide",
          "test_subtracts_two_numbers"
        ]
      )
      # each test span has test suite, module, and session
      expect(test_spans).to all have_test_tag(:test_suite_id)
      expect(test_spans).to all have_test_tag(:test_module_id)
      expect(test_spans).to all have_test_tag(:test_session_id)

      expect(agentless_logs).to have(3).items

      addition_log = agentless_logs.find { |log| log[:message].include?("Adding") }
      expect(addition_log).to be_present
      expect(addition_log[:message]).to include("Adding 1 and 2")
      expect(addition_log[:message]).to include("dd.span_id")
      addition_test_span = test_spans.find { |span| span.name == "test_adds_two_numbers" }
      expect(addition_log[:message]).to include(addition_test_span.id.to_s)
    end
  end

  context "when mixin creates methods dynamically" do
    before do
      Minitest::Runnable.reset
      require_relative "test/test_calculator_generated"
      Minitest.run([])
    end

    it "instruments this test session with agentless logs support" do
      # test session and module traced
      expect(test_session_span).not_to be_nil
      expect(test_module_span).not_to be_nil

      expect([test_session_span, test_module_span]).to all have_pass_status

      expect(test_suite_spans).to have(1).items
      expect(test_suite_spans).to have_tag_values_no_order(:status, ["pass"])
      expect(test_suite_spans).to have_tag_values_no_order(
        :suite,
        [
          "CalculatorGeneratedTest at spec/datadog/ci/contrib/rails/test/test_calculator_generated.rb"
        ]
      )

      # there is test span for every test case
      expect(test_spans).to have(5).items
      expect(test_spans).to have_tag_values_no_order(
        :name,
        [
          "test_adds_two_numbers",
          "test_performs_add",
          "test_performs_divide",
          "test_performs_multiply",
          "test_performs_subtract"
        ]
      )

      # each test span has test suite, module, and session
      expect(test_spans).to all have_test_tag(:test_suite_id)
      expect(test_spans).to all have_test_tag(:test_module_id)
      expect(test_spans).to all have_test_tag(:test_session_id)

      expect(agentless_logs).to have(5).items
    end
  end
end
