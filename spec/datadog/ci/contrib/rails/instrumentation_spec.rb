require "logger"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"
require "tempfile"

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

  context "with ActiveSupport parallel executor" do
    let(:marker_file) { Tempfile.new("datadog-active-support-parallel") }
    let(:marker_path) { marker_file.path }

    before do
      skip "ActiveSupport parallel executor regression runs on Rails 7+" if Rails.gem_version < Gem::Version.new("7.0")
      skip "ActiveSupport::TestCase.parallelize is not available" unless ActiveSupport::TestCase.respond_to?(:parallelize)

      Minitest::Runnable.reset
      Minitest.parallel_executor = nil
      Minitest.seed = 1
    end

    after do
      Minitest.parallel_executor = nil
      Minitest::Runnable.reset
      marker_file.close!
    end

    context "with threads" do
      before do
        run_active_support_parallel_tests(:threads)
      end

      it "sets active test in worker threads" do
        expect(worker_markers).to contain_exactly("test_one:true", "test_two:true")
      end

      it "instruments tests through Minitest" do
        expect(test_spans).to have(2).items
        expect(test_spans).to have_tag_values_no_order(:name, ["test_one", "test_two"])
        expect(test_spans).to all have_pass_status
        expect(test_spans).to all have_test_tag(:test_suite_id)
        expect(test_spans).to all have_test_tag(:test_module_id)
        expect(test_spans).to all have_test_tag(:test_session_id)
      end
    end

    context "with processes" do
      before do
        skip "Process parallelization requires fork support" unless Process.respond_to?(:fork)

        run_active_support_parallel_tests(:processes)
      end

      it "sets active test in worker processes" do
        expect(worker_markers).to contain_exactly("test_one:true", "test_two:true")
      end
    end
  end

  def run_active_support_parallel_tests(executor)
    path = marker_path
    executor_tag = executor.to_s
    parallelize_options = {workers: 2, with: executor}
    if ActiveSupport::TestCase.method(:parallelize).parameters.any? { |_, name| name == :threshold }
      parallelize_options[:threshold] = 0
    end

    klass = Class.new(ActiveSupport::TestCase) do
      parallelize(**parallelize_options)

      define_method(:record_active_test!) do
        active_test = Datadog::CI.active_test
        File.open(path, "a") do |file|
          file.puts("#{name}:#{!active_test.nil?}")
        end

        assert active_test, "expected Datadog::CI.active_test to be set"
        active_test.set_tag("active_support_parallel_executor", executor_tag)
      end

      define_method(:test_one) do
        record_active_test!
      end

      define_method(:test_two) do
        record_active_test!
      end
    end

    stub_const("ActiveSupportParallel#{executor.to_s.capitalize}Test", klass)

    expect(Minitest.run([])).to be(true)
  end

  def worker_markers
    File.readlines(marker_path, chomp: true)
  end
end
