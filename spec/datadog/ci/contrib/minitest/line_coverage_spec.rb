require "minitest"

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

RSpec.describe "Minitest instrumentation with per-test line coverage" do
  let(:line_coverage) { Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage }
  let(:fixture_path) { File.expand_path("../rspec/fixtures/line_coverage/geometry.rb", __dir__) }
  let(:fixture_file) { Datadog::CI::Git::LocalRepository.relative_to_root(fixture_path) }

  before do
    skip "per-test line coverage is not supported on this Ruby" unless line_coverage.supported?
  end

  after do
    line_coverage.stop_collector
  end

  include_context "CI mode activated" do
    let(:integration_name) { :minitest }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:line_coverage_enabled) { true }

    let(:test_management_enabled) { true }
    let(:test_properties) do
      {
        "LineCoverageMinitestSkips at spec/datadog/ci/contrib/minitest/line_coverage_spec.rb.test_disabled." => {
          "quarantined" => false,
          "disabled" => true,
          "attempt_to_fix" => false
        }
      }
    end
  end

  def lines_of(event)
    event&.inspect_coverage&.fetch(fixture_file, nil)
  end

  def test_span_named(name)
    test_spans.find { |span| span.name == name }
  end

  def run_minitest
    load fixture_path
    Minitest::Runnable.reset
    Minitest.seed = 1

    Class.new(Minitest::Test) do
      def self.name
        "LineCoverageMinitestSkips"
      end

      def test_passes
        assert_equal 4, LineCoverageGeometry::Square.new(2).area
      end

      def test_disabled
        LineCoverageGeometry::Square.new(2).area
      end

      def test_skips_itself
        LineCoverageGeometry::Square.new(2).area
        skip "not today"
      end
    end

    Minitest.run([])
  end

  it "sends no record for a test that Test Management disables, and the lines that ran for one that skips itself" do
    run_minitest

    expect(test_spans).to have(3).items
    expect(test_span_named("test_disabled")).to have_skip_status
    expect(find_coverage_for_test(test_span_named("test_disabled"))).to be_nil

    expect(test_span_named("test_skips_itself")).to have_skip_status
    expect(lines_of(find_coverage_for_test(test_span_named("test_skips_itself")))).to include(5, 6, 9)
    expect(lines_of(find_coverage_for_test(test_span_named("test_passes")))).to include(5, 6, 9)
  end
end
