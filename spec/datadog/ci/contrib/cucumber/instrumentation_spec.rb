require "stringio"
require "fileutils"
require "cucumber"
require "securerandom"

RSpec.describe "Cucumber instrumentation" do
  let(:integration) { Datadog::CI::Contrib::Instrumentation.fetch_integration(:cucumber) }
  let(:cucumber_features_root) { File.join(__dir__, "features") }
  let(:enable_retries_failed) { false }
  let(:single_test_retries_count) { 5 }
  let(:total_test_retries_limit) { 100 }

  let(:enable_retries_new) { false }
  let(:known_tests_set) { Set.new }
  let(:enable_impacted_tests) { false }

  let(:enable_test_management) { false }
  let(:test_properties_hash) { {} }

  let(:changed_files_set) { Set.new }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(cucumber_features_root)
  end

  include_context "CI mode activated" do
    let(:integration_name) { :cucumber }
    let(:integration_options) { {service_name: "jalapenos"} }

    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:tests_skipping_enabled) { true }

    let(:flaky_test_retries_enabled) { enable_retries_failed }
    let(:retry_failed_tests_max_attempts) { single_test_retries_count }
    let(:retry_failed_tests_total_limit) { total_test_retries_limit }

    let(:early_flake_detection_enabled) { enable_retries_new }
    let(:known_tests) { known_tests_set }

    let(:test_management_enabled) { enable_test_management }
    let(:test_properties) { test_properties_hash }

    let(:impacted_tests_enabled) { enable_impacted_tests }
    let(:changed_files) { changed_files_set }

    let(:bundle_path) { "step_definitions/helpers" }
  end

  let(:cucumber_9_or_above) { Gem::Version.new("9.0.0") <= integration.version }
  let(:cucumber_8_or_above) { Gem::Version.new("8.0.0") <= integration.version }
  let(:cucumber_4_or_above) { Gem::Version.new("4.0.0") <= integration.version }

  let(:run_id) { SecureRandom.random_number(2**64 - 1) }
  let(:steps_file_definition_path) { "spec/datadog/ci/contrib/cucumber/features/step_definitions/steps.rb" }
  let(:steps_file_for_run_path) do
    "spec/datadog/ci/contrib/cucumber/features/step_definitions/steps_#{run_id}.rb"
  end

  # Cucumber runtime setup
  let(:existing_runtime) { Cucumber::Runtime.new(runtime_options) }
  let(:runtime_options) { {} }
  # CLI configuration
  let(:feature_file_to_run) {}
  let(:features_path) { "spec/datadog/ci/contrib/cucumber/features/#{feature_file_to_run}" }
  let(:args) do
    [
      "-r",
      steps_file_for_run_path,
      features_path
    ]
  end
  let(:stdin) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:kernel) { double(:kernel) }

  let(:cli) do
    if cucumber_8_or_above
      Cucumber::Cli::Main.new(args, stdout, stderr, kernel)
    else
      Cucumber::Cli::Main.new(args, stdin, stdout, stderr, kernel)
    end
  end

  let(:expected_test_run_code) { 0 }

  before do
    # Ruby loads any file at most once per process, but we need to load
    # the cucumber step definitions multiple times for every Cucumber::Runtime we create
    # So we add a random number to the file path to force Ruby to load it again
    FileUtils.cp(
      steps_file_definition_path,
      steps_file_for_run_path
    )

    # assert that environment tags are collected once per session
    expect(Datadog::CI::Ext::Environment).to receive(:tags).once.and_call_original

    expect(kernel).to receive(:exit).with(expected_test_run_code)

    # do not use manual API
    expect(Datadog::CI).to receive(:start_test_session).never
    expect(Datadog::CI).to receive(:start_test_module).never
    expect(Datadog::CI).to receive(:start_test_suite).never
    expect(Datadog::CI).to receive(:start_test).never

    cli.execute!(existing_runtime)
  end

  after do
    FileUtils.rm(steps_file_for_run_path)
  end

  context "executing a passing test suite" do
    let(:feature_file_to_run) { "passing.feature" }

    it "creates spans for each scenario and step" do
      expect(test_spans).to have(4).items

      scenario_span = spans.find { |s| s.resource == "cucumber scenario" }

      expect(scenario_span.type).to eq("test")
      expect(scenario_span.name).to eq("cucumber scenario")
      expect(scenario_span.resource).to eq("cucumber scenario")
      expect(scenario_span.service).to eq("jalapenos")

      expect(scenario_span).to have_test_tag(:span_kind, "test")
      expect(scenario_span).to have_test_tag(:name, "cucumber scenario")
      expect(scenario_span).to have_test_tag(
        :suite,
        "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature"
      )
      expect(scenario_span).to have_test_tag(:type, "test")

      expect(scenario_span).to have_test_tag(:framework, "cucumber")
      expect(scenario_span).to have_test_tag(:framework_version, integration.version.to_s)

      expect(scenario_span).to have_pass_status

      expect(scenario_span).to have_test_tag(
        :source_file,
        "passing.feature"
      )
      expect(scenario_span).to have_test_tag(:source_start, "3")

      expect(scenario_span).to have_test_tag(
        :codeowners,
        "[\"@test-owner\"]"
      )

      # before hook was executed
      expect(scenario_span.get_tag("cucumber_before_hook_executed")).not_to be_nil

      step_span = spans.find { |s| s.resource == "datadog" }
      expect(step_span.name).to eq("datadog")

      expect(spans).to all have_origin(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
    end

    it "marks undefined cucumber scenario as skipped" do
      undefined_scenario_span = spans.find { |s| s.resource == "undefined scenario" }
      expect(undefined_scenario_span).not_to be_nil
      expect(undefined_scenario_span).to have_skip_status
      expect(undefined_scenario_span).to have_test_tag(:skip_reason, 'Undefined step: "undefined"')
    end

    it "marks pending cucumber scenario as skipped" do
      pending_scenario_span = spans.find { |s| s.resource == "pending scenario" }
      expect(pending_scenario_span).not_to be_nil
      expect(pending_scenario_span).to have_skip_status
      expect(pending_scenario_span).to have_test_tag(:skip_reason, "implementation")
    end

    it "marks skipped cucumber scenario as skipped" do
      skipped_scenario_span = spans.find { |s| s.resource == "skipped scenario" }
      expect(skipped_scenario_span).not_to be_nil
      expect(skipped_scenario_span).to have_skip_status
      expect(skipped_scenario_span).to have_test_tag(:skip_reason, "Scenario skipped")
    end

    it "creates test session span" do
      expect(test_session_span).not_to be_nil
      expect(test_session_span.service).to eq("jalapenos")
      expect(test_session_span).to have_test_tag(:span_kind, "test")
      expect(test_session_span).to have_test_tag(:framework, "cucumber")
      expect(test_session_span).to have_test_tag(:framework_version, integration.version.to_s)
      expect(test_session_span).to have_pass_status

      # ITR
      expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
      expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
      expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
      expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)

      # Total code coverage
      expect(test_session_span).to have_test_tag(:code_coverage_lines_pct)
    end

    it "creates test module span" do
      expect(test_module_span).not_to be_nil
      expect(test_module_span.name).to eq("cucumber")
      expect(test_module_span.service).to eq("jalapenos")
      expect(test_module_span).to have_test_tag(:span_kind, "test")
      expect(test_module_span).to have_test_tag(:framework, "cucumber")
      expect(test_module_span).to have_test_tag(
        :framework_version,
        integration.version.to_s
      )
      expect(test_module_span).to have_pass_status
    end

    it "creates test suite span" do
      expect(first_test_suite_span).not_to be_nil
      expect(first_test_suite_span.name).to eq("Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature")
      expect(first_test_suite_span.service).to eq("jalapenos")
      expect(first_test_suite_span).to have_test_tag(:span_kind, "test")
      expect(first_test_suite_span).to have_test_tag(:framework, "cucumber")
      expect(first_test_suite_span).to have_test_tag(
        :framework_version,
        integration.version.to_s
      )

      expect(first_test_suite_span).to have_test_tag(
        :source_file,
        "passing.feature"
      )
      expect(first_test_suite_span).to have_test_tag(:source_start, "1")

      expect(first_test_suite_span).to have_test_tag(
        :codeowners,
        "[\"@test-owner\"]"
      )

      expect(first_test_suite_span).to have_pass_status
    end

    it "connects test span to test session, test module, and test suite" do
      expect(first_test_span).to have_test_tag(:test_module_id, test_module_span.id.to_s)
      expect(first_test_span).to have_test_tag(:module, "cucumber")
      expect(first_test_span).to have_test_tag(:test_session_id, test_session_span.id.to_s)
      expect(first_test_span).to have_test_tag(:test_suite_id, first_test_suite_span.id.to_s)
      expect(first_test_span).to have_test_tag(:suite, first_test_suite_span.name)
    end

    context "collecting coverage with features dir as root" do
      before { skip if PlatformHelpers.jruby? }

      it "creates coverage events for each non-skipped test ignoring bundle_path" do
        expect(coverage_events).to have(1).item

        expect_coverage_events_belong_to_session(test_session_span)
        expect_coverage_events_belong_to_suite(first_test_suite_span)
        expect_coverage_events_belong_to_tests([test_spans.first])
        expect_non_empty_coverages

        feature_coverage = coverage_events.first.coverage
        # expect cucumber features to have gherkin files and step definitions as covered files
        expect(feature_coverage.size).to eq(2)
        expect(feature_coverage.keys).to include(
          match(%r{features/passing\.feature}),
          match(%r{features/step_definitions/steps_#{run_id}\.rb})
        )
      end
    end

    context "skipping a test" do
      let(:itr_skippable_tests) do
        Set.new([
          "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature.cucumber scenario."
        ])
      end

      it "skips the test" do
        expect(test_spans).to have(4).items
        expect(test_spans).to all have_skip_status

        itr_skipped_test = test_spans.find { |span| span.name == "cucumber scenario" }
        expect(itr_skipped_test).to have_test_tag(:itr_skipped_by_itr, "true")

        # check that hooks are not executed for skipped tests
        expect(itr_skipped_test.get_tag("cucumber_before_hook_executed")).to be_nil
        expect(itr_skipped_test.get_tag("cucumber_after_hook_executed")).to be_nil
        expect(itr_skipped_test.get_tag("cucumber_after_step_hook_executed")).to be_nil
      end

      it "sets session level tags" do
        expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
        expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 1)
      end
    end
  end

  context "executing a failing test suite" do
    let(:feature_file_to_run) { "failing.feature" }
    let(:expected_test_run_code) { 2 }

    it "creates all CI spans with failed state" do
      expect(first_test_span.name).to eq("cucumber failing scenario")
      expect(first_test_span).to have_fail_status

      step_span = spans.find { |s| s.resource == "failure" }
      expect(step_span.name).to eq("failure")
      expect(step_span).to have_fail_status

      expect(first_test_suite_span.name).to eq(
        "Datadog integration - test failing features at spec/datadog/ci/contrib/cucumber/features/failing.feature"
      )

      expect([first_test_suite_span, test_session_span, test_module_span]).to all have_fail_status
    end
  end

  context "executing a scenario with examples" do
    let(:feature_file_to_run) { "with_parameters.feature" }

    it "a single test suite, and a test span for each example with parameters JSON" do
      expect(test_spans).to have(3).items
      expect(test_suite_spans).to have(1).item

      test_spans.each_with_index do |span, index|
        # test parameters are available since cucumber 4
        if cucumber_4_or_above
          expect(span).to have_test_tag(:name, "scenario with examples")
          expect(span).to have_test_tag(
            :parameters,
            "{\"arguments\":{\"num1\":\"#{index}\",\"num2\":\"#{index + 1}\",\"total\":\"#{index + index + 1}\"},\"metadata\":{}}"
          )
        else
          expect(span).to have_test_tag(
            :name,
            "scenario with examples, Examples (##{index + 1})"
          )
          expect(span).not_to have_test_tag(:parameters)
        end
        expect(span).to have_test_tag(
          :suite,
          "Datadog integration for parametrized tests at spec/datadog/ci/contrib/cucumber/features/with_parameters.feature"
        )
        expect(span).to have_test_tag(:test_suite_id, first_test_suite_span.id.to_s)
        expect(span).not_to have_test_tag(:is_retry)
        expect(span).to have_pass_status
      end
    end

    context "skipping some tests" do
      before do
        skip("test parameters are not supported in cucumber 3") unless cucumber_4_or_above
      end

      let(:itr_skippable_tests) do
        Set.new([
          'Datadog integration for parametrized tests at spec/datadog/ci/contrib/cucumber/features/with_parameters.feature.scenario with examples.{"arguments":{"num1":"0","num2":"1","total":"1"},"metadata":{}}',
          'Datadog integration for parametrized tests at spec/datadog/ci/contrib/cucumber/features/with_parameters.feature.scenario with examples.{"arguments":{"num1":"2","num2":"3","total":"5"},"metadata":{}}'
        ])
      end

      it "skips the test" do
        expect(test_spans).to have(3).items
        expect(test_spans).to have_tag_values_no_order(:status, ["skip", "skip", "pass"])
      end

      it "sets session level tags" do
        expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_type, "test")
        expect(test_session_span).to have_test_tag(:itr_tests_skipped, "true")
        expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 2)
      end
    end
  end

  context "executing several features at once" do
    let(:expected_test_run_code) { 2 }

    let(:passing_test_suite) { test_suite_spans.find { |span| span.name =~ /passing/ } }
    let(:failing_test_suite) { test_suite_spans.find { |span| span.name =~ /failing/ } }

    it "creates a test suite span for each feature" do
      expect(test_suite_spans).to have(7).items
      expect(passing_test_suite).to have_pass_status
      expect(failing_test_suite).to have_fail_status
    end

    it "connects tests with their respective test suites" do
      cucumber_scenario = test_spans.find { |span| span.name =~ /cucumber scenario/ }
      expect(cucumber_scenario).to have_test_tag(:test_suite_id, passing_test_suite.id.to_s)

      cucumber_failing_scenario = test_spans.find { |span| span.name =~ /cucumber failing scenario/ }
      expect(cucumber_failing_scenario).to have_test_tag(:test_suite_id, failing_test_suite.id.to_s)
    end

    it "sets failed status for module and session" do
      expect([test_session_span, test_module_span]).to all have_fail_status
    end
  end

  context "executing a feature with undefined steps in strict mode" do
    let(:expected_test_run_code) { 2 }
    let(:feature_file_to_run) { "passing.feature" }
    let(:args) do
      [
        "--strict",
        "-r",
        steps_file_for_run_path,
        features_path
      ]
    end

    it "marks test session as failed" do
      expect(test_session_span).to have_fail_status
    end

    it "marks test suite as failed" do
      expect(first_test_suite_span).to have_fail_status
    end

    it "marks undefined cucumber scenario as failed" do
      undefined_scenario_span = spans.find { |s| s.resource == "undefined scenario" }
      expect(undefined_scenario_span).not_to be_nil
      expect(undefined_scenario_span).to have_fail_status
      expect(undefined_scenario_span).to have_error
      expect(undefined_scenario_span).to have_error_message("Undefined step: \"undefined\"")
    end

    it "marks pending cucumber scenario as failed" do
      pending_scenario_span = spans.find { |s| s.resource == "pending scenario" }
      expect(pending_scenario_span).to have_fail_status
    end

    it "marks skipped cucumber scenario as skipped" do
      skipped_scenario_span = spans.find { |s| s.resource == "skipped scenario" }
      expect(skipped_scenario_span).to have_skip_status
    end
  end

  context "executing a feature where all scenarios are skipped" do
    let(:feature_file_to_run) { "skipped.feature" }

    it "marks all test spans as skipped" do
      expect(test_spans).to have(2).items
      expect(test_spans).to all have_skip_status
    end

    it "marks test session as passed" do
      expect(test_session_span).to have_pass_status
    end

    it "marks test suite as skipped" do
      expect(first_test_suite_span).to have_skip_status
    end
  end

  context "executing a feature with unskippable scenario" do
    let(:feature_file_to_run) { "unskippable_scenario.feature" }

    let(:itr_skippable_tests) do
      Set.new([
        "Datadog integration at spec/datadog/ci/contrib/cucumber/features/unskippable_scenario.feature.unskippable scenario."
      ])
    end

    it "runs the test and adds forced run tag" do
      expect(test_spans).to have(1).item
      expect(first_test_span).to have_pass_status
      expect(first_test_span).to have_test_tag(:itr_forced_run, "true")
      expect(first_test_span).not_to have_test_tag(:itr_skipped_by_itr)

      expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
      expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)
    end
  end

  context "executing a feature with unskippable feature" do
    let(:feature_file_to_run) { "unskippable.feature" }

    let(:itr_skippable_tests) do
      Set.new([
        "Datadog integration at spec/datadog/ci/contrib/cucumber/features/unskippable.feature.unskippable scenario."
      ])
    end

    it "runs the test and adds forced run tag" do
      expect(test_spans).to have(1).item
      expect(first_test_span).to have_pass_status
      expect(first_test_span).to have_test_tag(:itr_forced_run, "true")

      expect(test_session_span).to have_test_tag(:itr_tests_skipped, "false")
      expect(test_session_span).to have_test_tag(:itr_test_skipping_count, 0)
    end
  end

  context "executing flaky test scenario with Cucumber's built in retry mechanism" do
    let(:max_retries_count) { 5 }

    let(:feature_file_to_run) { "flaky.feature" }

    let(:args) do
      [
        "--retry",
        max_retries_count.to_s,
        "-r",
        steps_file_for_run_path,
        features_path
      ]
    end

    it "retries the test several times and correctly tracks result of every invocation" do
      # 1 initial run of flaky test + 4 retries until pass + 1 passing test + 1 other flaky + 4 retries until pass = 11 spans
      expect(test_spans).to have(11).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(8).items # see steps.rb
      expect(passed_spans).to have(3).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["very flaky scenario"]).to have(5).items
      expect(test_spans_by_test_name["another flaky scenario"]).to have(5).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(8)

      # We set retry reason to "external" when the test is retried outside of datadog-ci gem
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_EXTERNAL] * 8)

      # count how many spans were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(0)

      expect(test_spans_by_test_name["this scenario just passes"]).to have(1).item

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
    end
  end

  context "executing flaky test scenario with datadog-ci's failed test retries" do
    let(:enable_retries_failed) { true }
    let(:feature_file_to_run) { "flaky.feature" }

    it "retries the test several times and correctly tracks result of every invocation" do
      # 1 initial run of flaky test + 4 retries until pass + 1 passing test + 1 other flaky + 4 retries = 11 spans
      expect(test_spans).to have(11).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(8).items # see steps.rb
      expect(passed_spans).to have(3).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["very flaky scenario"]).to have(5).items
      expect(test_spans_by_test_name["another flaky scenario"]).to have(5).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(8)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 8)

      # count how many spans were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(0)

      expect(test_spans_by_test_name["this scenario just passes"]).to have(1).item

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
    end

    context "when max retries attempts configuration value is too low" do
      let(:single_test_retries_count) { 1 }
      let(:expected_test_run_code) { 2 }

      it "retries the test once" do
        # 1 initial run of flaky test + 1 retry + 1 passing + 1 other flaky + 1 retry = 5 spans
        expect(test_spans).to have(5).items
        retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
        expect(retries_count).to eq(2)

        # check retry reasons
        retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
        expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 2)

        # count how many spans were marked as new
        new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
        expect(new_tests_count).to eq(0)

        failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
        expect(failed_spans).to have(4).items
        expect(passed_spans).to have(1).items

        expect(test_suite_spans).to have(1).item
        expect(test_suite_spans.first).to have_fail_status

        expect(test_session_span).to have_fail_status
      end
    end

    context "when total limit of failed tests to retry is 1" do
      let(:total_test_retries_limit) { 1 }
      let(:expected_test_run_code) { 2 }

      it "does not retry the test" do
        # 1 initial run of flaky test + 4 retries + 1 passing + 1 failed run of flaky test = 7 spans
        expect(test_spans).to have(7).items
        retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
        expect(retries_count).to eq(4)

        # check retry reasons
        retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
        expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_FAILED] * 4)

        # count how many spans were marked as new
        new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
        expect(new_tests_count).to eq(0)

        failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
        expect(failed_spans).to have(5).items
        expect(passed_spans).to have(2).items

        expect(test_suite_spans).to have(1).item
        expect(test_suite_spans.first).to have_fail_status

        expect(test_session_span).to have_fail_status
      end
    end
  end

  context "executing a feature with Datadog's new test retries aka early flake detection" do
    let(:feature_file_to_run) { "passing.feature" }
    let(:enable_retries_new) { true }
    let(:known_tests_set) do
      Set.new(
        [
          "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature.pending scenario.",
          "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature.skipped scenario."
        ]
      )
    end

    it "retries passing test and doesn't retry undefined test" do
      # 1 initial run of passing test + 10 retries + 3 skipped tests = 14 spans
      expect(test_spans).to have(14).items

      skipped_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "skip" }
      expect(skipped_spans).to have(3).items # see steps.rb
      expect(passed_spans).to have(11).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["cucumber scenario"]).to have(11).items
      expect(test_spans_by_test_name["undefined scenario"]).to have(1).item

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY] * 10)

      # count how many spans were marked as new
      new_tests_count = test_spans.count { |span| span.get_tag("test.is_new") == "true" }
      expect(new_tests_count).to eq(12)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end

  context "executing failing test scenario with quarantined test" do
    let(:feature_file_to_run) { "failing.feature" }

    let(:enable_test_management) { true }
    let(:test_properties_hash) do
      {
        "Datadog integration - test failing features at spec/datadog/ci/contrib/cucumber/features/failing.feature.cucumber failing scenario." => {
          "quarantined" => true,
          "disabled" => false
        }
      }
    end

    it "skips the test without failing the build" do
      expect(test_spans).to have(1).item

      quarantined_test_span = test_spans.first

      expect(quarantined_test_span).to have_skip_status
      expect(quarantined_test_span).to have_test_tag(:skip_reason, "Flaky test is disabled by Datadog")
      expect(quarantined_test_span).to have_test_tag(:is_quarantined)
      expect(quarantined_test_span).not_to have_test_tag(:is_test_disabled)
      expect(quarantined_test_span).not_to have_test_tag(:is_attempt_to_fix)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_skip_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:test_management_enabled, "true")
    end
  end

  context "executing failing test scenario with disabled test" do
    let(:feature_file_to_run) { "failing.feature" }

    let(:enable_test_management) { true }
    let(:test_properties_hash) do
      {
        "Datadog integration - test failing features at spec/datadog/ci/contrib/cucumber/features/failing.feature.cucumber failing scenario." => {
          "quarantined" => false,
          "disabled" => true
        }
      }
    end

    it "skips the test without failing the build" do
      expect(test_spans).to have(1).item

      disabled_test_span = test_spans.first

      expect(disabled_test_span).to have_skip_status
      expect(disabled_test_span).to have_test_tag(:skip_reason, "Flaky test is disabled by Datadog")
      expect(disabled_test_span).not_to have_test_tag(:is_quarantined)
      expect(disabled_test_span).to have_test_tag(:is_test_disabled)
      expect(disabled_test_span).not_to have_test_tag(:is_attempt_to_fix)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_skip_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:test_management_enabled, "true")
    end
  end

  context "executing failing test scenario with attempt to fix" do
    let(:feature_file_to_run) { "failing.feature" }
    let(:expected_test_run_code) { 2 }

    let(:enable_test_management) { true }
    let(:test_properties_hash) do
      {
        "Datadog integration - test failing features at spec/datadog/ci/contrib/cucumber/features/failing.feature.cucumber failing scenario." => {
          "quarantined" => false,
          "disabled" => false,
          "attempt_to_fix" => true
        }
      }
    end

    it "retries the test several times and fails the build as test is not disabled nor quarantined" do
      # 1 original execution and 12 retries (attempt_to_fix_retries_count)
      expect(test_spans).to have(attempt_to_fix_retries_count + 1).items

      failed_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "fail" }
      expect(failed_spans).to have(attempt_to_fix_retries_count + 1).items
      expect(passed_spans).to have(0).item

      # count how many tests were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(attempt_to_fix_retries_count)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq(["attempt_to_fix"] * attempt_to_fix_retries_count)

      # count how many tests were marked as attempt_to_fix
      attempt_to_fix_count = test_spans.count { |span| span.get_tag("test.test_management.is_attempt_to_fix") == "true" }
      expect(attempt_to_fix_count).to eq(attempt_to_fix_retries_count + 1)

      # last retry is tagged with has_failed_all_retries
      failed_all_retries_count = test_spans.count { |span| span.get_tag("test.has_failed_all_retries") }
      expect(failed_all_retries_count).to eq(1)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_fail_status

      expect(test_session_span).to have_fail_status
      expect(test_session_span).to have_test_tag(:test_management_enabled, "true")
    end
  end

  context "executing a feature with Datadog's early flake detection and impacted tests detection enabled" do
    let(:feature_file_to_run) { "passing.feature" }
    let(:enable_retries_new) { true }
    let(:enable_impacted_tests) { true }

    let(:known_tests_set) do
      Set.new(
        [
          "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature.pending scenario.",
          "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature.cucumber scenario.",
          "Datadog integration at spec/datadog/ci/contrib/cucumber/features/passing.feature.skipped scenario."
        ]
      )
    end

    let(:changed_files_set) do
      Set.new(
        [
          "passing.feature:1:1"
        ]
      )
    end

    it "retries modified test" do
      # 1 initial run of passing test + 10 retries + 3 skipped tests = 14 spans
      expect(test_spans).to have(14).items

      skipped_spans, passed_spans = test_spans.partition { |span| span.get_tag("test.status") == "skip" }
      expect(skipped_spans).to have(3).items # see steps.rb
      expect(passed_spans).to have(11).items

      test_spans_by_test_name = test_spans.group_by { |span| span.get_tag("test.name") }
      expect(test_spans_by_test_name["cucumber scenario"]).to have(11).items

      # count how many spans were marked as retries
      retries_count = test_spans.count { |span| span.get_tag("test.is_retry") == "true" }
      expect(retries_count).to eq(10)

      # check retry reasons
      retry_reasons = test_spans.map { |span| span.get_tag("test.retry_reason") }.compact
      expect(retry_reasons).to eq([Datadog::CI::Ext::Test::RetryReason::RETRY_DETECT_FLAKY] * 10)

      # modified tests - all tests are marked as modified because we don't have end lines in cucumber
      modified_count = test_spans.count { |span| span.get_tag("test.is_modified") == "true" }
      expect(modified_count).to eq(14)

      expect(test_suite_spans).to have(1).item
      expect(test_suite_spans.first).to have_pass_status

      expect(test_session_span).to have_pass_status
      expect(test_session_span).to have_test_tag(:early_flake_enabled, "true")
    end
  end
end
