# frozen_string_literal: true

require "open3"
require_relative "../../../../support/contexts/framework_file_dependencies"

RSpec.describe "RSpec file dependencies" do
  include_context "framework file dependencies"
  let(:integration_name) { :rspec }

  def run_framework
    reader = read_fixtures
    with_new_rspec_environment do
      RSpec.describe "Fixture readers" do
        it("reads fixtures") { Thread.new { reader.call }.value }
        it("does not read fixtures") {}
      end
      options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format progress])
      expect(RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)).to eq(0)
    end
  end

  it_behaves_like "file dependencies from the framework runner"

  it "preserves Ruby's argument validation order for a lazy report export" do
    require_relative "fixtures/lazy_report_export"
    fixture = File.expand_path("fixtures/lazy_report_export.rb", __dir__)
    baseline_path = File.join(fixture_directory, "baseline.csv")
    output, status = Open3.capture2e(RbConfig.ruby, "-r", fixture, "-e", <<~RUBY, baseline_path)
      abort "File.read is instrumented" unless File.method(:read).owner == IO.singleton_class
      report = FileDependencyFixtures::LazyReportExport.new(ARGV.fetch(0))
      begin
        File.read(report, nil, "invalid-offset")
        abort "Expected TypeError"
      rescue TypeError
      end
    RUBY
    expect(status.success?).to be(true), output
    generated_without_instrumentation = File.exist?(baseline_path)
    report_path = File.join(fixture_directory, "report.csv")

    with_new_rspec_environment do
      RSpec.describe "Report downloads" do
        it "rejects an invalid offset without extra export generation" do
          report = FileDependencyFixtures::LazyReportExport.new(report_path)

          expect { File.read(report, nil, "invalid-offset") }.to raise_error(TypeError)
          expect(File.exist?(report_path)).to eq(generated_without_instrumentation)
        end
      end
      options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format progress])
      output = StringIO.new
      expect(RSpec::Core::Runner.new(options).run(StringIO.new, output)).to eq(0), output.string
    end
  end

  it "does not leak dependencies from a group skipped in before(:context) into the next group" do
    require_relative "fixtures/user"
    require_relative "fixtures/order"

    with_new_rspec_environment do
      RSpec.describe "User integration" do
        before(:context) do
          @user = ContextCoverageHelper::User.new("John", "Doe")
          skip "External service unavailable"
        end

        it("sends the user to the external service") { raise "Skipped example must not run" }
      end

      RSpec.describe "Orders" do
        it "calculates the total" do
          order = ContextCoverageHelper::Order.new
          order.add_item(10)
          expect(order.total).to eq(10)
        end
      end

      options = RSpec::Core::ConfigurationOptions.new(%w[--pattern none --format progress --order defined])
      output = StringIO.new
      expect(RSpec::Core::Runner.new(options).run(StringIO.new, output)).to eq(0)
      expect(output.string).to include("2 examples, 0 failures, 1 pending")
    end

    test = test_spans.find { |span| span.name == "calculates the total" }
    expect(test).to have_pass_status
    event = file_events.find { |candidate| candidate.fetch("span_id") == test.id }
    dependencies = event.fetch("files").map { |file| file.fetch("filename") }
    expect(dependencies).to include("spec/datadog/ci/contrib/rspec/fixtures/order.rb")
    expect(dependencies).not_to include("spec/datadog/ci/contrib/rspec/fixtures/user.rb")
  end

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
            Thread.new { File.open(paths[0]).tap { |file| file.read }.close }.value
          end
          after(:context) do
            stages << :after
            Thread.new { File.binread(Pathname.new(paths[2])) }.value
          end
          2.times do |index|
            it("reads fixture #{index}") do
              stages << :test
              Thread.new { File.read(Pathname.new(paths[1])) }.value
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
        before(:context) { Thread.new { File.open(paths[0]).tap { |file| file.read }.close }.value }
        it("outer example") {}

        context "left" do
          before(:context) { Thread.new { File.read(Pathname.new(paths[1])) }.value }
          it("first example") {}
          it("second example") {}
        end

        context "right" do
          before(:context) { Thread.new { File.binread(Pathname.new(paths[2])) }.value }
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
