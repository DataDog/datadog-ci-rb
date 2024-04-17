require "stringio"
require "fileutils"
require "cucumber"

RSpec.describe "Cucumber formatter" do
  let(:cucumber_features_root) { File.join(__dir__, "features") }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(cucumber_features_root)
  end

  include_context "CI mode activated" do
    let(:integration_name) { :cucumber }
    let(:integration_options) { {service_name: "jalapenos"} }

    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
  end

  let(:cucumber_8_or_above) { Gem::Version.new("8.0.0") <= Datadog::CI::Contrib::Cucumber::Integration.version }
  let(:cucumber_4_or_above) { Gem::Version.new("4.0.0") <= Datadog::CI::Contrib::Cucumber::Integration.version }

  let(:run_id) { rand(1..2**64 - 1) }
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

    expect(Datadog::CI::Ext::Environment).to receive(:tags).never
    expect(kernel).to receive(:exit).with(expected_test_run_code)

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
      expect(scenario_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )

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
      expect(test_session_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(test_session_span).to have_pass_status
    end

    it "creates test module span" do
      expect(test_module_span).not_to be_nil
      expect(test_module_span.name).to eq("cucumber")
      expect(test_module_span.service).to eq("jalapenos")
      expect(test_module_span).to have_test_tag(:span_kind, "test")
      expect(test_module_span).to have_test_tag(:framework, "cucumber")
      expect(test_module_span).to have_test_tag(
        :framework_version,
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
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
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
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

      it "creates coverage events for each non-skipped test" do
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
        expect(span).to have_pass_status
      end
    end
  end

  context "executing several features at once" do
    let(:expected_test_run_code) { 2 }

    let(:passing_test_suite) { test_suite_spans.find { |span| span.name =~ /passing/ } }
    let(:failing_test_suite) { test_suite_spans.find { |span| span.name =~ /failing/ } }

    it "creates a test suite span for each feature" do
      expect(test_suite_spans).to have(4).items
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
end
