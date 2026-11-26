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
  let(:browser_options) { Ferrum::Browser::Options.new }
  let(:visit_result) { Object.new }
  let(:navigation_methods) do
    [:visit, :goto, :go_to].select { |method| Capybara::Cuprite::Browser.method_defined?(method) }
  end
  let(:browser) do
    instance_double(
      Capybara::Cuprite::Browser,
      :cookies => cookies_spy,
      :current_url => current_url,
      :options => browser_options,
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

    allow(Capybara::Cuprite::Browser).to receive(:new).and_return(browser)
    allow(browser).to receive(:evaluate) do |script|
      executed_scripts << script
      true
    end
    if reset_url
      allow(browser).to receive(:reset) do
        allow(browser).to receive(:current_url).and_return(reset_url)
      end
    end
    allow(browser).to receive(:base_url=)
    navigation_methods.each do |method|
      allow(browser).to receive(method) do |url|
        visited_urls << url
        visit_result
      end
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
    rum_active = Datadog::CI::Ext::RUM::SCRIPT_IS_RUM_ACTIVE
    stop_rum = Datadog::CI::Ext::RUM::SCRIPT_STOP_RUM_SESSION
    expect(executed_scripts).to eq(["(function() {\n#{rum_active}\n})()", "(function() {\n#{stop_rum}\n})()"] * 2)

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
    expect(first_test_span).to have_test_tag(:browser_name, "chrome")
    expect(first_test_span).to have_test_tag(:browser_version, "mockversion")

    expect(first_test_span).to have_test_tag(:is_rum_active, "true")
  end

  context "when the browser name is configured" do
    let(:browser_options) { Ferrum::Browser::Options.new(browser_name: "chromium") }

    it "reports the configured browser name" do
      expect(first_test_span).to have_test_tag(:browser_name, "chromium")
    end
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

  describe "driver lifecycle" do
    let(:driver) { Capybara::Cuprite::Driver.new(nil) }

    it "skips RUM teardown when the driver has never used a browser" do
      expect(browser).not_to receive(:evaluate)

      driver.quit
    end

    it "preserves the visit result when navigation instrumentation fails" do
      allow(Datadog::CI).to receive(:active_test).and_raise(StandardError, "test lookup failed")
      expect(Datadog.logger).to receive(:warn).with(/Could not record browser navigation.*test lookup failed/)

      expect(driver.visit(current_url)).to equal(visit_result)
    end

    it "preserves exceptions from the underlying driver" do
      driver.browser
      failure = StandardError.new("browser operation failed")
      navigation_methods.each { |method| allow(browser).to receive(method).and_raise(failure) }
      allow(browser).to receive(:reset).and_raise(failure)
      allow(browser).to receive(:quit).and_raise(failure)

      expect { driver.visit(current_url) }.to raise_error { |error| expect(error).to equal(failure) }
      expect { driver.reset! }.to raise_error { |error| expect(error).to equal(failure) }
      expect { driver.quit }.to raise_error { |error| expect(error).to equal(failure) }
    end

    it "resets and quits the driver when RUM instrumentation fails" do
      driver.browser
      allow(browser).to receive(:evaluate).and_raise(StandardError, "script failed")
      expect(Datadog.logger).to receive(:warn).with(/during reset!.*script failed/)
      expect(Datadog.logger).to receive(:warn).with(/during quit.*script failed/)
      expect(browser).to receive(:reset)
      quit_result = Object.new
      expect(browser).to receive(:quit).and_return(quit_result)

      driver.reset!
      expect(driver.quit).to equal(quit_result)
    end
  end
end
