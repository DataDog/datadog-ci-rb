require "knapsack_pro"
require "fileutils"

RSpec.describe "Knapsack Pro runner when Datadog::CI is configured during the knapsack run like in rspec_go rake task" do
  before do
    # expect that public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
  end

  # Yields to a block in a new RSpec global context. All RSpec
  # test configuration and execution should be wrapped in this method.
  def with_new_rspec_environment
    old_configuration = ::RSpec.configuration
    old_world = ::RSpec.world
    ::RSpec.configuration = ::RSpec::Core::Configuration.new
    ::RSpec.world = ::RSpec::Core::World.new

    yield
  ensure
    ::RSpec.configuration = old_configuration
    ::RSpec.world = old_world
  end

  def devnull
    File.new("/dev/null", "w")
  end

  before do
    allow_any_instance_of(Datadog::Core::Remote::Negotiation).to(
      receive(:endpoint?).with("/evp_proxy/v4/").and_return(true)
    )

    allow(Datadog::CI::Utils::TestRun).to receive(:command).and_return("knapsack:queue:rspec")

    allow_any_instance_of(KnapsackPro::Runners::Queue::RSpecRunner).to receive(:test_file_paths).and_return(
      ["./spec/datadog/ci/contrib/knapsack_rspec_go/suite_under_test/some_test_rspec.rb"],
      []
    )

    # raise to prevent Knapsack from running Kernel.exit(0)
    allow(KnapsackPro::Report).to receive(:save_node_queue_to_api).and_raise(ArgumentError)
  end

  it "instruments this rspec session" do
    with_new_rspec_environment do
      ClimateControl.modify(
        "KNAPSACK_PRO_CI_NODE_BUILD_ID" => "144",
        "KNAPSACK_PRO_TEST_SUITE_TOKEN_RSPEC" => "example_token",
        "KNAPSACK_PRO_FIXED_QUEUE_SPLIT" => "true",
        "KNAPSACK_PRO_QUEUE_ID" => nil
      ) do
        KnapsackPro::Adapters::RSpecAdapter.bind
        KnapsackPro::Runners::Queue::RSpecRunner.run("--require knapsack_helper", devnull, devnull)
      rescue ArgumentError
        # suppress invalid API key error
      end
    end

    # test session and module traced
    expect(test_session_span).not_to be_nil
    expect(test_module_span).not_to be_nil

    # test session and module are failed
    expect([test_session_span, test_module_span]).to all have_fail_status

    # single test suite span
    expect(test_suite_spans).to have(1).item
    expect(test_suite_spans.first).to have_test_tag(:status, Datadog::CI::Ext::Test::Status::FAIL)
    expect(test_suite_spans.first).to have_test_tag(
      :suite,
      "SomeTest at ./spec/datadog/ci/contrib/knapsack_rspec_go/suite_under_test/some_test_rspec.rb"
    )

    # there is test span for every test case
    expect(test_spans).to have(2).items
    # test spans belong to a single test suite
    expect(test_spans).to have_unique_tag_values_count(:test_suite_id, 1)
    expect(test_spans).to have_tag_values_no_order(
      :status,
      [Datadog::CI::Ext::Test::Status::FAIL, Datadog::CI::Ext::Test::Status::PASS]
    )

    # every test span is connected to test module and test session
    expect(test_spans).to all have_test_tag(:test_module_id)
    expect(test_spans).to all have_test_tag(:test_session_id)
  end
end
