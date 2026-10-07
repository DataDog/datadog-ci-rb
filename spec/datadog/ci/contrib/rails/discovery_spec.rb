# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe "Rails plugin test discovery" do
  let(:fixture_directory) { File.realpath(Dir.mktmpdir("rails-plugin-discovery")) }
  let(:test_file) { File.join(fixture_directory, "test", "discovery_test.rb") }
  let(:execution_marker) { File.join(fixture_directory, "executed.txt") }
  let(:discovery_file) { File.join(fixture_directory, "tests.json") }

  before do
    FileUtils.mkdir_p(File.dirname(test_file))
    File.write(test_file, <<~RUBY)
      require "logger"
      require "active_support"
      require "active_support/test_case"

      class PluginDiscoveryTest < ActiveSupport::TestCase
        def test_one
          File.open(#{execution_marker.inspect}, "a") { |file| file.puts(name) }
          assert true
        end

        def test_two
          File.open(#{execution_marker.inspect}, "a") { |file| file.puts(name) }
          assert true
        end
      end
    RUBY
  end

  after do
    FileUtils.remove_entry(fixture_directory)
  end

  it "loads and runs the selected test file during normal execution" do
    stdout, stderr, status = run_plugin_tests(discovery: false)

    expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
    expect(stdout).to include("2 runs, 2 assertions, 0 failures, 0 errors")
    expect(File.readlines(execution_marker, chomp: true)).to contain_exactly("test_one", "test_two")
  end

  it "discovers the selected test file without executing test bodies" do
    # Rails 8.1 loads test files while processing Minitest arguments, after autorun starts.
    expect_discovery(arguments: ["--seed", "123", test_file])
  end

  it "discovers the default test selection without executing test bodies" do
    expect_discovery(arguments: [])
  end

  def expect_discovery(arguments:)
    stdout, stderr, status = run_plugin_tests(discovery: true, arguments: arguments)

    expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
    expect(File.exist?(execution_marker)).to be(false)
    expect(File.exist?(discovery_file)).to be(true),
      "Rails plugin discovery exited successfully without a report. stdout:\n#{stdout}\nstderr:\n#{stderr}"

    records = File.readlines(discovery_file).map { |line| JSON.parse(line) }
    expect(records).to contain_exactly(
      a_hash_including("name" => "test_one", "module" => "minitest", "suiteSourceFile" => "test/discovery_test.rb"),
      a_hash_including("name" => "test_two", "module" => "minitest", "suiteSourceFile" => "test/discovery_test.rb")
    )
  end

  def run_plugin_tests(discovery:, arguments: [test_file])
    requires = discovery ? ["-rdatadog/ci/auto_instrument"] : []

    Open3.capture3(
      {
        "RUBYOPT" => nil,
        "DD_CIVISIBILITY_ENABLED" => discovery ? "1" : "0",
        "DD_CIVISIBILITY_AGENTLESS_ENABLED" => "true",
        "DD_API_KEY" => "dummy_key",
        "DD_TEST_OPTIMIZATION_DISCOVERY_ENABLED" => discovery ? "1" : "0",
        "DD_TEST_OPTIMIZATION_DISCOVERY_FILE" => discovery_file,
        "DD_INSTRUMENTATION_TELEMETRY_ENABLED" => "false"
      },
      RbConfig.ruby,
      "-rbundler/setup",
      "-I#{File.expand_path("../../../../../lib", __dir__)}",
      *requires,
      "-e", 'require "rails/plugin/test"',
      "--", *arguments,
      chdir: fixture_directory
    )
  end
end
