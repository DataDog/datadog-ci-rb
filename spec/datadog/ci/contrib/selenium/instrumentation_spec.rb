require "cucumber"
require "selenium-webdriver"

RSpec.describe "Browser tests with selenium" do
  let(:cucumber_features_root) { File.join(__dir__, "features") }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(cucumber_features_root)
  end

  include_context "CI mode activated" do
    let(:integration_name) { :cucumber }
  end

  let(:manager) { spy("manager") }
  let(:bridge) do
    instance_double(
      Selenium::WebDriver::Remote::Bridge,
      create_session: nil,
      browser: "mockbrowser",
      capabilities: double("capabilities", browser_version: "mockversion", "[]": "mockcapabilities"),
      window_handles: ["window"],
      switch_to_window: true,
      manage: manager,
      find_elements_by: [],
      extend: true,
      send: true,
      quit: true
    )
  end

  let(:stdin) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  let(:kernel) { double(:kernel) }

  # Cucumber runtime setup
  let(:existing_runtime) { Cucumber::Runtime.new(runtime_options) }
  let(:runtime_options) { {} }
  # CLI configuration
  let(:features_path) { "spec/datadog/ci/contrib/selenium/features" }
  let(:args) do
    [
      "-r",
      "spec/datadog/ci/contrib/selenium/features/step_definitions/steps.rb",
      features_path
    ]
  end

  let(:cli) do
    Cucumber::Cli::Main.new(args, stdout, stderr, kernel)
  end
  let(:expected_test_run_code) { 0 }

  # spies
  let(:executed_scripts) { [] }
  let(:visited_urls) { [] }

  before do
    # expect(kernel).to receive(:exit).with(expected_test_run_code)
    expect(Selenium::WebDriver::Remote::Bridge).to receive(:new).and_return(bridge)
    allow(bridge).to receive(:execute_script) do |script|
      executed_scripts << script
      "true"
    end
    allow(bridge).to receive(:get) do |url|
      visited_urls << url
    end

    expect(kernel).to receive(:exit).with(expected_test_run_code)
    ClimateControl.modify("DD_CIVISIBILITY_SELENIUM_ENABLED" => "1", "DD_CIVISIBILITY_RUM_FLUSH_WAIT_MILLIS" => "1") do
      cli.execute!(existing_runtime)
    end
  end

  it "recognize the test as browser test and adds additional tags" do
    expect(visited_urls).to eq(["http://www.example.com", "about:blank"])
    expect(executed_scripts).to eq(
      [
        Datadog::CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE,
        Datadog::CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION,
        "window.sessionStorage.clear()",
        "window.localStorage.clear()",
        Datadog::CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE,
        Datadog::CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION
      ]
    )

    expect(test_spans).to have(1).item

    expect(manager).to have_received(:add_cookie).with(
      {name: "datadog-ci-visibility-test-execution-id", value: first_test_span.trace_id.to_s}
    )
    expect(manager).to have_received(:delete_cookie).with("datadog-ci-visibility-test-execution-id").twice

    expect(first_test_span).to have_test_tag(:type, "browser")
    expect(first_test_span).to have_test_tag(:browser_driver, "selenium")
    expect(first_test_span).to have_test_tag(
      :browser_driver_version,
      Gem.loaded_specs["selenium-webdriver"].version.to_s
    )
    expect(first_test_span).to have_test_tag(:browser_name, "mockbrowser")
    expect(first_test_span).to have_test_tag(:browser_version, "mockversion")

    expect(first_test_span).to have_test_tag(:is_rum_active, "true")
  end
end
