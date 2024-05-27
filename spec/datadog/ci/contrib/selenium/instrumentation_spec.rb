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

  before do
    expect(kernel).to receive(:exit).with(expected_test_run_code)
    cli.execute!(existing_runtime)
  end

  it "recognize the test as browser test and adds additional tags" do
    expect(test_spans).to have(1).item

    expect(first_test_span).to have_test_tag(:type, "browser")
    expect(first_test_span).to have_test_tag(:browser_driver, "selenium")
    expect(first_test_span).to have_test_tag(
      :browser_driver_version,
      Gem.loaded_specs["selenium-webdriver"].version.to_s
    )
  end
end
