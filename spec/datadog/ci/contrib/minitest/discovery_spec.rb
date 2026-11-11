# frozen_string_literal: true

require "json"
require "logger"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"
require "minitest"
require "minitest/spec"
require_relative "helpers/shared_discovery_tests"

RSpec.describe "Minitest discovery source files" do
  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:test_discovery_enabled) { true }
  end

  let(:fixture_path) { "spec/datadog/ci/contrib/minitest/helpers/discovery_test.rb" }
  let(:shared_path) { "spec/datadog/ci/contrib/minitest/helpers/shared_discovery_tests.rb" }

  before do
    Minitest::Runnable.reset
  end

  after do
    Minitest::Runnable.reset
  end

  it "discovers executable files for shared, nested, generated, anonymous and ordinary tests without changing identities" do
    tests = discover_fixture

    expected_suites = [
      "CustomerContract at #{shared_path}",
      "CustomerContract::shared nested context at #{shared_path}",
      "CustomerContract::nested context at #{shared_path}",
      "SimpleModel at #{fixture_path}",
      "GeneratedContract0 at #{shared_path}",
      "GeneratedContract1 at #{shared_path}",
      " at #{shared_path}",
      "MinitestDiscoveryFixtures::ClassContract at #{fixture_path}",
      "MinitestDiscoveryFixtures::SpecContract at #{shared_path}",
      "MinitestDiscoveryFixtures::InheritedContract at #{shared_path}"
    ]
    # The shared base class is itself runnable in Minitest. Keep it in discovery
    # rather than removing it from the framework's registry to fit expectations.
    expect(tests).to contain_exactly(
      *expected_suites.map { |suite| hash_including("suite" => suite, "suiteSourceFile" => fixture_path) },
      hash_including("suite" => "SharedDiscoveryBase at #{shared_path}", "suiteSourceFile" => shared_path)
    )
    expect(tests).to include(hash_including("suite" => "CustomerContract at #{shared_path}", "name" => "test_contract"))
  end

  it "uses legacy attribution when specs were defined before instrumentation" do
    tests = discover_fixture(instrument_after_definition: true)

    expect(tests).to include(hash_including(
      "suite" => "CustomerContract at #{shared_path}",
      "name" => "test_contract",
      "suiteSourceFile" => shared_path
    ))
  end

  context "when a named spec class is reopened in separate files" do
    let(:first_file) { "spec/datadog/ci/contrib/minitest/helpers/reopened_first_test.rb" }
    let(:second_file) { "spec/datadog/ci/contrib/minitest/helpers/reopened_second_test.rb" }

    it "runs both tests natively, together and as independently loaded files" do
      [[first_file], [second_file], [first_file, second_file]].each do |files|
        stdout, stderr, status = Open3.capture3(
          {"RUBYOPT" => nil, "DD_CIVISIBILITY_ENABLED" => "false"},
          RbConfig.ruby, "-rbundler/setup", "-e",
          'ARGV.each { |file| require File.expand_path(file) }; exit(Minitest.run(["--no-plugins"]) ? 0 : 1)',
          *files
        )

        expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
        expect(stdout).to include("EXECUTED_REOPENED_FIRST") if files.include?(first_file)
        expect(stdout).to include("EXECUTED_REOPENED_SECOND") if files.include?(second_file)
      end
    end

    it "discovers each test under the file that must be loaded to execute it" do
      tests = discover_fixture(fixture_paths: [first_file, second_file])

      expect(tests).to contain_exactly(
        hash_including(
          "name" => "test_from_first_file",
          "suite" => "ReopenedDiscoverySpec at #{first_file}",
          "suiteSourceFile" => first_file
        ),
        hash_including(
          "name" => "test_from_second_file",
          "suite" => "ReopenedDiscoverySpec at #{second_file}",
          "suiteSourceFile" => second_file
        )
      )
    end
  end

  it "logs a real capture failure when a customer's inheritance hook freezes the subclass" do
    output = StringIO.new
    Datadog.configure { |c| c.logger.instance = Logger.new(output) }
    parent = Class.new(Minitest::Spec) do
      include SharedDiscoveryMethods

      def self.inherited(subclass)
        subclass.freeze
        super
      end
    end

    klass = Class.new(parent)

    expect(klass).to be_frozen
    expect(Minitest::Runnable.runnables).to include(klass)
    expect(klass.dd_spec_source_file).to be_nil
    expect(output.string).to include("WARN", "Could not capture Minitest spec definition", "FrozenError")
    expect(klass.new("test_shared_nested").run.passed?).to be true
  end

  context "during execution" do
    let(:test_discovery_enabled) { false }

    it "preserves shared-method source attribution" do
      Class.new(Minitest::Spec) { include SharedDiscoveryMethods }

      expect(Minitest.run([])).to be true
      expect(first_test_span).to have_test_tag(:suite, " at #{shared_path}")
      expect(first_test_span).to have_test_tag(:source_file, shared_path)
      expect(first_test_suite_span).to have_test_tag(:source_file, shared_path)
    end
  end

  def discover_fixture(instrument_after_definition: false, fixture_paths: [fixture_path])
    Dir.mktmpdir("minitest-discovery") do |directory|
      output_path = File.join(directory, "tests.json")
      fixture_files = fixture_paths.map { |path| File.expand_path(path) }
      # Use a fresh Ruby process: RSpec deliberately undefines the global
      # describe DSL on Module, so real Minitest fixtures cannot run beside it.
      script = <<~RUBY
        require "minitest/spec"
        require "datadog/ci"
        #{fixture_files.inspect}.each { |file| require file } if #{instrument_after_definition}
        Datadog.configure do |c|
          c.ci.enabled = true
          c.ci.agentless_mode_enabled = true
          c.api_key = "unused-discovery-key"
          c.ci.test_discovery_enabled = true
          c.ci.test_discovery_output_path = #{output_path.inspect}
          c.ci.instrument :minitest
        end
        #{fixture_files.inspect}.each { |file| require file } unless #{instrument_after_definition}
        exit(Minitest.run(["--no-plugins"]) ? 0 : 1)
      RUBY
      stdout, stderr, status = Open3.capture3(
        {"RUBYOPT" => nil},
        RbConfig.ruby, "-rbundler/setup", "-I#{File.expand_path("../../../../../lib", __dir__)}", "-e", script
      )

      expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
      expect(stdout).not_to include("EXECUTED_SHARED_", "EXECUTED_REOPENED_")
      expect(File.exist?(output_path)).to be(true), "Missing discovery output. stdout:\n#{stdout}\nstderr:\n#{stderr}"
      File.readlines(output_path).map { |line| JSON.parse(line) }
    end
  end
end
