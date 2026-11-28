# frozen_string_literal: true

require "cucumber"
require_relative "../../../../support/contexts/framework_file_dependencies"

RSpec.describe "Cucumber file dependencies" do
  include_context "framework file dependencies"
  let(:integration_name) { :cucumber }

  def run_framework
    feature = File.join(fixture_directory, "readers.feature")
    steps = File.join(fixture_directory, "steps.rb")
    File.write(feature, <<~FEATURE)
      Feature: File dependencies
        Scenario: reads fixtures
          Given I read the fixture files
        Scenario: does not read fixtures
          Given I do not read files
    FEATURE
    File.write(steps, <<~RUBY)
      Given("I read the fixture files") do
        File.open(File.join(__dir__, "open.txt")) { |file| file.read }
        File.read(File.join(__dir__, "read.txt"))
        File.binread(File.join(__dir__, "binread.txt"))
      end
      Given("I do not read files") {}
    RUBY
    args = ["--require", steps, feature, "--format", "progress"]
    exit_handler = double("exit handler")
    expect(exit_handler).to receive(:exit).with(0)
    output = StringIO.new
    version = Gem.loaded_specs.fetch("cucumber").version
    cli = if version >= Gem::Version.new("8.0.0")
      Cucumber::Cli::Main.new(args, output, output, exit_handler)
    else
      Cucumber::Cli::Main.new(args, StringIO.new, output, output, exit_handler)
    end
    cli.execute!(Cucumber::Runtime.new)
  end

  it_behaves_like "file dependencies from the framework runner"

  context "with per-test line coverage" do
    include_context "framework line coverage"

    it "names the feature file, without lines, in the record of the scenario" do
      run_framework
      feature = Datadog::CI::Git::LocalRepository.relative_to_root(File.join(fixture_directory, "readers.feature"))

      reader = file_events.find { |event| fixture_dependencies(event).any? }
      expect(reader.fetch("files")).to include({"filename" => feature})
    end
  end
end
