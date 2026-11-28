# frozen_string_literal: true

require "tmpdir"
require "stringio"

RSpec.shared_context "framework file dependencies" do
  include_context "CI mode activated"

  # The native collector caches its repository boundaries per thread. Give each
  # runner its own thread so it cannot inherit or change another spec's roots.
  around { |example| Thread.new { example.run }.value }

  let(:itr_enabled) { true }
  let(:code_coverage_enabled) { true }
  let(:file_events) { [] }
  let(:fixture_directory) { Dir.mktmpdir("framework-file-dependencies-", Datadog::CI::Git::LocalRepository.root) }
  let(:fixture_paths) { %w[open.txt read.txt binread.txt].map { |name| File.join(fixture_directory, name) } }
  let(:read_fixtures) do
    paths = fixture_paths
    lambda do
      File.open(paths[0]).tap { |file| file.read }.close
      File.read(paths[1])
      File.binread(paths[2])
    end
  end

  before do
    fixture_paths.each { |path| File.write(path, "fixture content") }
    allow(Datadog.send(:components).test_impact_analysis).to receive(:write) do |event|
      file_events << MessagePack.unpack(MessagePack.pack(event))
    end
  end

  after { FileUtils.remove_entry(fixture_directory) }

  def fixture_dependencies(event)
    expected = fixture_paths.map { |path| Datadog::CI::Git::LocalRepository.relative_to_root(path) }
    event.fetch("files").map { |file| file.fetch("filename") }.select { |path| expected.include?(path) }
  end
end

RSpec.shared_context "framework line coverage" do
  let(:line_coverage_enabled) { true }
  let(:line_coverage) { Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage }

  before do
    require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
    skip "per-test line coverage is not supported on this Ruby" unless line_coverage.supported?
  end

  after { line_coverage.stop_collector }
end

RSpec.shared_examples "file dependencies from the framework runner" do
  it "attributes all three hooks only to the test that reads the fixtures" do
    run_framework
    expect(test_spans.size).to eq(2)
    expect(test_spans).to all have_pass_status
    expect(file_events.size).to eq(2)
    expect(file_events.map { |event| fixture_dependencies(event).size }.sort).to eq([0, 3])
    recorded = file_events.flat_map { |event| fixture_dependencies(event) }
    expect(recorded).to match_array(fixture_paths.map { |path| Datadog::CI::Git::LocalRepository.relative_to_root(path) })
    expect(file_events.map { |event| event.fetch("span_id") }).to match_array(test_spans.map { |test| test.id })
  end

  context "with coverage disabled" do
    let(:code_coverage_enabled) { false }

    it "still runs the tests without emitting coverage" do
      run_framework
      expect(test_spans.size).to eq(2)
      expect(test_spans).to all have_pass_status
      expect(file_events).to be_empty
    end
  end

  context "with suite-level TIA" do
    let(:tia_test_skipping_mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE }

    it "aggregates the dependencies into the suite payload" do
      run_framework
      expect(test_spans.size).to eq(2)
      expect(test_spans).to all have_pass_status
      expect(file_events.size).to eq(1)
      expect(fixture_dependencies(file_events.first).size).to eq(3)
      expect(file_events.first).not_to have_key("span_id")
    end
  end

  context "with per-test line coverage" do
    include_context "framework line coverage"

    it "names the fixtures, without lines, only in the record of the test that reads them" do
      run_framework
      expect(test_spans.size).to eq(2)
      expect(test_spans).to all have_pass_status

      readers = file_events.select { |event| fixture_dependencies(event).any? }
      expect(readers.size).to eq(1)
      expect(fixture_dependencies(readers.first)).to match_array(
        fixture_paths.map { |path| Datadog::CI::Git::LocalRepository.relative_to_root(path) }
      )
      expect(test_spans.map(&:id)).to include(readers.first.fetch("span_id"))

      fixture_entries = readers.first.fetch("files").select { |file| fixture_dependencies(readers.first).include?(file["filename"]) }
      expect(fixture_entries).to all(satisfy { |file| !file.key?("bitmap") })
    end
  end
end
