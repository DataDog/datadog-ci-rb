require "stringio"
require "cucumber"

RSpec.describe "Cucumber formatter" do
  extend ConfigurationHelpers

  include_context "CI mode activated" do
    let(:integration_name) { :cucumber }
    let(:integration_options) { {service_name: "jalapenos"} }
  end

  # Cucumber runtime setup
  let(:existing_runtime) { Cucumber::Runtime.new(runtime_options) }
  let(:runtime_options) { {} }
  # CLI configuration
  let(:args) { [] }
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
    let(:args) do
      [
        "-r",
        "spec/datadog/ci/contrib/cucumber/features/step_definitions",
        "spec/datadog/ci/contrib/cucumber/features/passing.feature"
      ]
    end

    def do_execute
      cli.execute!(existing_runtime)
    end

    it "creates spans for each scenario and step" do
      expect(Datadog::CI::Ext::Environment).to receive(:tags).never

      expect(kernel).to receive(:exit).with(0)

      do_execute

      scenario_span = spans.find { |s| s.resource == "cucumber scenario" }
      step_span = spans.find { |s| s.resource == "datadog" }

      expect(scenario_span.resource).to eq("cucumber scenario")
      expect(scenario_span.service).to eq("jalapenos")
      expect(scenario_span.span_type).to eq(Datadog::CI::Ext::AppTypes::TYPE_TEST)
      expect(scenario_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(scenario_span.name).to eq("cucumber scenario")
      # expect(scenario_span)

      expect(step_span.resource).to eq("datadog")

      spans.each do |span|
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN))
          .to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
      end
    end

    it "creates test sesion span" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(test_session_span).not_to be_nil
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(test_session_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::TEST_TYPE
      )
      expect(test_session_span.service).to eq("jalapenos")
    end

    it "creates test module span" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(test_module_span).not_to be_nil
      expect(test_module_span.name).to eq(test_session_span.name)
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::FRAMEWORK
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_FRAMEWORK_VERSION)).to eq(
        Datadog::CI::Contrib::Cucumber::Integration.version.to_s
      )
      expect(test_module_span.get_tag(Datadog::CI::Ext::Test::TAG_TYPE)).to eq(
        Datadog::CI::Contrib::Cucumber::Ext::TEST_TYPE
      )
      expect(test_module_span.service).to eq("jalapenos")
    end

    it "connects scenario span to test session and test module" do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_MODULE_ID)).to eq(test_module_span.id.to_s)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_MODULE)).to eq(test_module_span.name)
      expect(first_test_span.get_tag(Datadog::CI::Ext::Test::TAG_TEST_SESSION_ID)).to eq(test_session_span.id.to_s)
    end
  end
end
