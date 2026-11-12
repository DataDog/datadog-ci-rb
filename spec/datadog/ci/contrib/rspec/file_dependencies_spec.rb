# frozen_string_literal: true

require_relative "../../../../support/contexts/framework_file_dependencies"

RSpec.describe "RSpec file dependencies" do
  include_context "framework file dependencies"
  let(:integration_name) { :rspec }

  def run_framework
    reader = read_fixtures
    with_new_rspec_environment do
      RSpec.describe "Fixture readers" do
        it("reads fixtures") { reader.call }
        it("does not read fixtures") {}
      end
      options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format progress])
      expect(RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)).to eq(0)
    end
  end

  it_behaves_like "file dependencies from the framework runner"

  context "with suite skipping enabled" do
    let(:tia_test_skipping_mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE }
    let(:tests_skipping_enabled) { true }
    let(:read_stages) { [] }

    def run_suite_framework
      paths = fixture_paths
      stages = read_stages
      with_new_rspec_environment do
        RSpec.describe "Suite fixture readers" do
          before(:context) do
            stages << :before
            File.open(paths[0]).tap { |file| file.read }.close
          end
          after(:context) do
            stages << :after
            File.binread(paths[2])
          end
          2.times do |index|
            it("reads fixture #{index}") do
              stages << :test
              File.read(paths[1])
            end
          end
        end
        RSpec.describe "Unrelated suite" do
          it("does not read fixtures") {}
        end
        options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format progress])
        expect(RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)).to eq(0)
      end
    end

    it "aggregates setup, test, and teardown reads into one deduplicated suite payload" do
      run_suite_framework

      expect(read_stages).to eq([:before, :test, :test, :after])
      expect(test_spans.size).to eq(3)
      expect(test_spans).to all have_pass_status
      expect(file_events.size).to eq(2)
      expect(test_session_span).to have_test_tag(:itr_test_skipping_enabled, "true")
      test_suite_spans.each do |suite|
        event = file_events.find { |candidate| candidate.fetch("test_suite_id") == suite.id }
        expected = if suite.name.start_with?("Suite fixture readers at ")
          fixture_paths.map { |path| Datadog::CI::Git::LocalRepository.relative_to_root(path) }
        else
          []
        end
        expect(fixture_dependencies(event)).to match_array(expected)
        expect(event).not_to have_key("span_id")
      end
    end

    context "when the reader suite is skippable" do
      let(:itr_skippable_suites) do
        Set.new(["Suite fixture readers at ./spec/datadog/ci/contrib/rspec/file_dependencies_spec.rb"])
      end

      it "skips its file reads and emits coverage only for the unrelated suite" do
        run_suite_framework

        expect(read_stages).to be_empty
        expect(test_spans.size).to eq(1)
        skipped_suite = test_suite_spans.find { |suite| suite.name.start_with?("Suite fixture readers at ") }
        expect(skipped_suite).to have_skip_status
        expect(skipped_suite).to have_test_tag(:itr_skipped_by_itr, "true")
        expect(file_events.size).to eq(1)
        expect(file_events.first.fetch("test_suite_id")).not_to eq(skipped_suite.id)
        expect(fixture_dependencies(file_events.first)).to be_empty
        expect(file_events.first).not_to have_key("span_id")
      end
    end
  end

  it "attributes before(:context) file reads to every descendant without leaking across contexts" do
    paths = fixture_paths
    with_new_rspec_environment do
      RSpec.describe "Context fixture readers" do
        before(:context) { File.open(paths[0]).tap { |file| file.read }.close }
        it("outer example") {}

        context "left" do
          before(:context) { File.read(paths[1]) }
          it("first example") {}
          it("second example") {}
        end

        context "right" do
          before(:context) { File.binread(paths[2]) }
          it("first example") {}
          it("second example") {}
        end
      end

      RSpec.describe "Unrelated group" do
        it("unrelated example") {}
      end

      options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format progress])
      expect(RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)).to eq(0)
    end

    expect(test_spans.size).to eq(6)
    expect(test_spans).to all have_pass_status
    expect(file_events.size).to eq(6)
    expected = {
      "outer example" => [paths[0]],
      "left first example" => paths.values_at(0, 1),
      "left second example" => paths.values_at(0, 1),
      "right first example" => paths.values_at(0, 2),
      "right second example" => paths.values_at(0, 2),
      "unrelated example" => []
    }
    test_spans.each do |test|
      event = file_events.find { |candidate| candidate.fetch("span_id") == test.id }
      dependencies = expected.fetch(test.name).map { |path| Datadog::CI::Git::LocalRepository.relative_to_root(path) }
      expect(fixture_dependencies(event)).to match_array(dependencies), "Unexpected dependencies for #{test.name}"
    end
  end
end
