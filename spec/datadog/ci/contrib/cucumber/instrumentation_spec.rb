require "stringio"
require "fileutils"
require "cucumber"

RSpec.describe "Cucumber formatter" do
  extend ConfigurationHelpers

  def do_execute
    cli.execute!(existing_runtime)
  end

  include_context "CI mode activated" do
    let(:integration_name) { :cucumber }
    let(:integration_options) { {service_name: "jalapenos"} }
  end

  let(:steps_file_id) { rand(1..2**64 - 1) }
  let(:steps_file_definition_path) { "spec/datadog/ci/contrib/cucumber/features/step_definitions/steps.rb" }
  let(:steps_file_for_run_path) do
    "spec/datadog/ci/contrib/cucumber/features/step_definitions/steps_#{steps_file_id}.rb"
  end

  before do
    # Ruby loads any file at most once per process, but we need to load
    # the cucumber step definitions multiple times for every Cucumber::Runtime we create
    # So we add a random number to the file path to force Ruby to load it again
    FileUtils.cp(
      steps_file_definition_path,
      steps_file_for_run_path
    )
  end

  after do
    FileUtils.rm(steps_file_for_run_path)
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
    cucumber_8 = Gem::Version.new("8.0.0")

    if Datadog::CI::Contrib::Cucumber::Integration.version < cucumber_8
      Cucumber::Cli::Main.new(args, stdin, stdout, stderr, kernel)
    else
      Cucumber::Cli::Main.new(args, stdout, stderr, kernel)
    end
  end

  context "executing a passing test suite" do
    let(:feature_file_to_run) { "passing.feature" }

    it "creates spans for each scenario and step" do
      expect(Datadog::CI::Ext::Environment).to receive(:tags).never

      expect(kernel).to receive(:exit).with(0)

      do_execute

      scenario_span = spans.find { |s| s.resource == "cucumber scenario" }

      expect(scenario_span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
      expect(scenario_span.name).to eq("cucumber scenario")
      expect(scenario_span.resource).to eq("cucumber scenario")
      expect(scenario_span.service).to eq("jalapenos")

      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_NAME)).to eq("cucumber scenario")
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(
        "spec/datadog/ci/contrib/cucumber/features/passing.feature"
      )
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(Datadog::CI::Ext::Test::TEST_TYPE)
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)

      step_span = spans.find { |s| s.resource == "datadog" }
      expect(step_span.resource).to eq("datadog")

      spans.each do |span|
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN))
          .to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
      end
    end

    it "creates test session span" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(test_session_span).not_to be_nil
      expect(test_session_span.service).to eq("jalapenos")
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
        Datadog::CI::Ext::AppTypes::TYPE_TEST
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Ext::Test::TEST_TYPE
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)
    end

    it "creates test module span" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(test_module_span).not_to be_nil
      expect(test_module_span.name).to eq(test_command)
      expect(test_module_span.service).to eq("jalapenos")
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
        Datadog::CI::Ext::AppTypes::TYPE_TEST
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Ext::Test::TEST_TYPE
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)
    end

    it "creates test suite span" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(test_suite_span).not_to be_nil
      expect(test_suite_span.name).to eq(features_path)
      expect(test_suite_span.service).to eq("jalapenos")
      expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_SPAN_KIND)).to eq(
        Datadog::CI::Ext::AppTypes::TYPE_TEST
      )
      expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Ext::Test::TEST_TYPE
      )
      expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(Datadog::CI::Ext::Test::Status::PASS)
    end

    it "connects scenario span to test session and test module" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID)).to eq(test_module_span.id.to_s)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_MODULE)).to eq(test_command)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID)).to eq(test_session_span.id.to_s)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SUITE_ID)).to eq(test_suite_span.id.to_s)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_SUITE)).to eq(test_suite_span.name)
    end
  end

  context "executing a failing test suite" do
    let(:feature_file_to_run) { "failing.feature" }

    it "creates all CI spans with failed state" do
      expect(kernel).to receive(:exit).with(2)

      do_execute

      expect(first_test_span.name).to eq("cucumber failing scenario")
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::FAIL
      )

      step_span = spans.find { |s| s.resource == "failure" }
      expect(step_span.name).to eq("failure")
      expect(step_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::FAIL
      )

      expect(test_suite_span.name).to eq(features_path)
      expect(test_suite_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::FAIL
      )

      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::FAIL
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_STATUS)).to eq(
        Datadog::CI::Ext::Test::Status::FAIL
      )
    end
  end
end
