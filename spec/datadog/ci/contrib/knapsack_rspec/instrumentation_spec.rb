require "knapsack_pro"
require "fileutils"

RSpec.describe "Knapsack Pro runner when Datadog::CI is configured during the knapsack run like in rspec_go rake task" do
  let(:integration) { Datadog::CI::Contrib::Instrumentation.fetch_integration(:rspec) }

  before do
    # expect that public manual API isn't used
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never
  end

  include_context "CI mode activated"

  before do
    allow(Datadog::CI::Utils::TestRun).to receive(:command).and_return("knapsack:queue:rspec")

    allow_any_instance_of(KnapsackPro::Runners::Queue::RSpecRunner).to receive(:test_file_paths).and_return(
      ["./spec/datadog/ci/contrib/knapsack_rspec/suite_under_test/some_test_rspec.rb"],
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
    expect(test_session_span).to have_test_tag(:framework, "rspec")
    expect(test_session_span).to have_test_tag(:framework_version, integration.version.to_s)

    expect(test_module_span).not_to be_nil

    # test session and module are failed
    expect([test_session_span, test_module_span]).to all have_fail_status

    # single test suite span
    expect(test_suite_spans).to have(1).item
    expect(test_suite_spans.first).to have_test_tag(:status, Datadog::CI::Ext::Test::Status::FAIL)
    expect(test_suite_spans.first).to have_test_tag(
      :suite,
      "SomeTest at ./spec/datadog/ci/contrib/knapsack_rspec/suite_under_test/some_test_rspec.rb"
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

  context "when the queue API becomes unavailable after a completed batch and fallback is disabled" do
    let(:batch_connection) do
      instance_double(
        KnapsackPro::Client::Connection,
        # Assign only the passing example, as Knapsack's split-by-example mode does.
        call: {"test_files" => [{"path" => "./spec/datadog/ci/contrib/knapsack_rspec/suite_under_test/some_test_rspec.rb[1:1:1]"}]},
        success?: true,
        errors?: false,
        api_code: nil
      )
    end
    let(:failed_connection) do
      instance_double(KnapsackPro::Client::Connection, call: nil, success?: false, errors?: false)
    end

    before do
      # Exercise the real allocator: it raises FallbackModeError when a connection fails.
      allow_any_instance_of(KnapsackPro::Runners::Queue::RSpecRunner).to receive(:test_file_paths).and_call_original
      expect(KnapsackPro::Client::Connection).to receive(:new).ordered.and_return(batch_connection)
      expect(KnapsackPro::Client::Connection).to receive(:new).ordered.and_return(failed_connection)
      expect(KnapsackPro::Report).not_to receive(:save_node_queue_to_api)
    end

    it "finishes failed parent events for the completed tests before Knapsack exits" do
      with_new_rspec_environment do
        ClimateControl.modify(
          "KNAPSACK_PRO_CI_NODE_BUILD_ID" => "144",
          "KNAPSACK_PRO_TEST_SUITE_TOKEN_RSPEC" => "example_token",
          "KNAPSACK_PRO_FIXED_QUEUE_SPLIT" => "true",
          "KNAPSACK_PRO_QUEUE_ID" => nil,
          "KNAPSACK_PRO_TEST_QUEUE_ID" => "144",
          "KNAPSACK_PRO_TEST_FILES_ENCRYPTED" => "false",
          "KNAPSACK_PRO_FALLBACK_MODE_ENABLED" => "false",
          "KNAPSACK_PRO_FALLBACK_MODE_ERROR_EXIT_CODE" => "42"
        ) do
          KnapsackPro::Adapters::RSpecAdapter.bind

          # Run only the passing example so the parent failure must come from the interrupted run.
          expect do
            KnapsackPro::Runners::Queue::RSpecRunner.run("--require knapsack_helper", devnull, devnull)
          end.to raise_error(SystemExit) { |error|
            expect(error.status).to eq(42)
            expect(error.cause).to be_a(KnapsackPro::QueueAllocator::FallbackModeError)
          }
        end
      end

      expect(test_spans).to have(1).item
      expect(test_spans).to all have_pass_status

      aggregate_failures "completed parent events" do
        expect(test_module_span).not_to be_nil
        expect(test_session_span).not_to be_nil
      end
      expect([test_module_span, test_session_span]).to all have_fail_status
      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans).to all have_pass_status
      expect(test_spans).to all have_test_tag(:test_module_id, test_module_span.id.to_s)
      expect(test_spans).to all have_test_tag(:test_session_id, test_session_span.id.to_s)
    end
  end
end
