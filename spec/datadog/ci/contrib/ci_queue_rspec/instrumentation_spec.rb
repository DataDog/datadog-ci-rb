require "rspec/queue"
require "fileutils"
require "securerandom"

RSpec.describe "RSpec instrumentation with Shopify's ci-queue runner" do
  before do
    # expect that public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:flaky_test_retries_enabled) { true }
  end

  let(:run_id) { SecureRandom.random_number(2**64 - 1) }
  let(:options) do
    RSpec::Core::ConfigurationOptions.new([
      "-Ispec/datadog/ci/contrib/ci_queue_rspec/suite_under_test",
      "--queue",
      "list:.%2Fspec%2Fdatadog%2Fci%2Fcontrib%2Fci_queue_rspec%2Fsuite_under_test%2Fsome_test_rspec.rb%5B1%3A1%3A1%5D:.%2Fspec%2Fdatadog%2Fci%2Fcontrib%2Fci_queue_rspec%2Fsuite_under_test%2Fsome_test_rspec.rb%5B1%3A1%3A2%5D:.%2Fspec%2Fdatadog%2Fci%2Fcontrib%2Fci_queue_rspec%2Fsuite_under_test%2Fsome_test_rspec.rb%5B1%3A1%3A3%5D",
      "--require",
      "some_test_rspec.rb",
      "--build",
      run_id.to_s,
      "--worker",
      "1",
      "--default-path",
      "spec/datadog/ci/contrib/ci_queue_rspec/suite_under_test"
    ])
  end

  before do
    FileUtils.mkdir("log")
  end

  after do
    FileUtils.rm_rf("log")
  end

  it "instruments this rspec session" do
    with_new_rspec_environment do
      ::RSpec::Queue::Runner.new(options).run(devnull, devnull)
    end

    # test session and module traced
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    # test session and module are failed
    expect([test_session_span, test_module_span]).to all have_fail_status

    # test suite spans are created for each test as for parallel execution
    expect(test_suite_spans).to have(3).items
    expect(test_suite_spans).to have_tag_values_no_order(
      :status,
      [Datadog::CI::Ext::Test::Status::FAIL, Datadog::CI::Ext::Test::Status::PASS, Datadog::CI::Ext::Test::Status::SKIP]
    )
    expect(test_suite_spans).to have_tag_values_no_order(
      :suite,
      [
        "SomeTest at ./spec/datadog/ci/contrib/ci_queue_rspec/suite_under_test/some_test_rspec.rb (ci-queue running example [nested fails])",
        "SomeTest at ./spec/datadog/ci/contrib/ci_queue_rspec/suite_under_test/some_test_rspec.rb (ci-queue running example [nested foo])",
        "SomeTest at ./spec/datadog/ci/contrib/ci_queue_rspec/suite_under_test/some_test_rspec.rb (ci-queue running example [nested is skipped])"
      ]
    )

    # there is test span for every test case + 5 retries
    expect(test_spans).to have(8).items
    # each test span has its own test suite
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 3)

    # every test span is connected to test module and test session
    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)
  end

  it "preserves per-example suite links for context failures with ci-queue loaded" do
    # The queue runner does not support context hooks, but requiring ci-queue
    # decorates examples even when they are run by the standard RSpec runner.
    with_new_rspec_environment do
      load File.expand_path("../rspec/fixtures/before_context_failure.rb", __dir__)
      options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
      expect(RSpec::Core::Runner.new(options).run(devnull, devnull)).to eq(1)
    end

    expect(test_spans).to have(3).items
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 3)
    test_spans.each do |span|
      suite = test_suite_spans.find do |candidate|
        candidate.id.to_s == span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID)
      end
      expect(suite).not_to be_nil
      expect(suite).to have_test_tag(:suite, span.get_tag("test.suite"))
      expect(suite).to have_test_tag(:status, span.get_tag("test.status"))
    end
    expect(test_spans).to all have_test_tag(:test_module_id, test_module_span.id.to_s)
    expect(test_spans).to all have_test_tag(:test_session_id, test_session_span.id.to_s)
  end
end
