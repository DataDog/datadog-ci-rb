require "fileutils"
require "securerandom"
require "cucumber"
require "capybara/cuprite"

RSpec.describe "Browser tests with cuprite" do
  let(:cucumber_features_root) { File.join(__dir__, "features") }

  before do
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(cucumber_features_root)
  end

  include_context "CI mode activated" do
    let(:integration_name) { :cucumber }
  end

  let(:reset_url) { nil }
  let(:current_url) { "http://www.example.com" }
  let(:cookies_spy) { instance_spy(Ferrum::Cookies) }
  let(:browser) do
    instance_double(
      Capybara::Cuprite::Browser,
      :cookies => cookies_spy,
      :current_url => current_url,
      :options => instance_double(Ferrum::Browser::Options, browser_name: "mockbrowser"),
      :version => instance_double(Ferrum::Browser::VersionInfo, product: "mockversion"),
      :raise_on_unhandled_modal= => nil,
      :url_blacklist= => nil,
      :url_whitelist= => nil,
      :reset => nil,
      :quit => nil
    )
  end

  let(:stdin) { StringIO.new }
  # let(:stdout) { StringIO.new }
  # let(:stderr) { StringIO.new }
  let(:stdout) { $stdout }
  let(:stderr) { $stderr }

  let(:kernel) { double(:kernel) }

  let(:steps_file_definition_path) { "spec/datadog/ci/contrib/cuprite/features/step_definitions/steps.rb" }
  let(:steps_file_for_run_path) do
    "spec/datadog/ci/contrib/cuprite/features/step_definitions/steps_#{SecureRandom.hex(8)}.rb"
  end

  # Cucumber runtime setup
  let(:existing_runtime) { Cucumber::Runtime.new(runtime_options) }
  let(:runtime_options) { {} }
  # CLI configuration
  let(:features_path) { "spec/datadog/ci/contrib/cuprite/features" }
  let(:args) do
    [
      "-r",
      steps_file_for_run_path,
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
    FileUtils.cp(steps_file_definition_path, steps_file_for_run_path)

    expect(Capybara::Cuprite::Browser).to receive(:new).and_return(browser)
    allow(browser).to receive(:evaluate_func) do |script|
      executed_scripts << script
      "true"
    end
    allow(browser).to receive(:visit) do |url|
      visited_urls << url
    end
    if reset_url
      allow(browser).to receive(:reset) do
        allow(browser).to receive(:current_url).and_return(reset_url)
      end
    end
    allow(browser).to receive(:base_url=)
    allow(browser).to receive(:goto) do |url|
      visited_urls << url
    end

    if Capybara::Cuprite.respond_to?(:deprecation_warning)
      expect(Capybara::Cuprite).not_to receive(:deprecation_warning)
    end

    expect(kernel).to receive(:exit).with(expected_test_run_code)
    ClimateControl.modify("DD_CIVISIBILITY_SELENIUM_ENABLED" => "1", "DD_CIVISIBILITY_RUM_FLUSH_WAIT_MILLIS" => "1") do
      cli.execute!(existing_runtime)
    end
  end

  after do
    FileUtils.rm(steps_file_for_run_path)
  end

  it "reports the browser test and its tags" do
    expect(visited_urls).to eq(["http://www.example.com"])
    expect(executed_scripts).to eq(
      [
        Datadog::CI::Contrib::Cuprite::ScriptExecutor::WRAPPED_SCRIPTS[Datadog::CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE],
        Datadog::CI::Contrib::Cuprite::ScriptExecutor::WRAPPED_SCRIPTS[Datadog::CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION],
        Datadog::CI::Contrib::Cuprite::ScriptExecutor::WRAPPED_SCRIPTS[Datadog::CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE],
        Datadog::CI::Contrib::Cuprite::ScriptExecutor::WRAPPED_SCRIPTS[Datadog::CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION]
      ]
    )

    expect(test_spans).to have(1).item

    expect(cookies_spy).to have_received(:set).with(
      {name: "datadog-ci-visibility-test-execution-id", value: first_test_span.trace_id.to_s, domain: "www.example.com"}
    )
    expect(cookies_spy).to have_received(:remove).with(
      {name: "datadog-ci-visibility-test-execution-id", domain: "www.example.com"}
    ).twice

    expect(first_test_span).to have_test_tag(:type, "browser")
    expect(first_test_span).to have_test_tag(:browser_driver, "cuprite")
    expect(first_test_span).to have_test_tag(
      :browser_driver_version,
      Gem.loaded_specs["cuprite"].version.to_s
    )
    expect(first_test_span).to have_test_tag(:browser_name, "mockbrowser")
    expect(first_test_span).to have_test_tag(:browser_version, "mockversion")

    expect(first_test_span).to have_test_tag(:is_rum_active, "true")
  end

  context "when navigation redirects to another host" do
    let(:current_url) { "https://redirected.example.com/landing" }

    it "sets and removes the cookie on the current host" do
      expect(visited_urls).to eq(["http://www.example.com"])
      expect(cookies_spy).to have_received(:set).with(
        name: "datadog-ci-visibility-test-execution-id",
        value: first_test_span.trace_id.to_s,
        domain: "redirected.example.com"
      )
      expect(cookies_spy).to have_received(:remove).with(
        name: "datadog-ci-visibility-test-execution-id", domain: "redirected.example.com"
      ).twice
    end
  end

  context "when reset clears the current URL" do
    let(:reset_url) { "about:blank" }

    it "quits without removing a cookie from a blank page" do
      expect(cookies_spy).to have_received(:remove).once
      expect(browser).to have_received(:quit)
    end
  end
end
