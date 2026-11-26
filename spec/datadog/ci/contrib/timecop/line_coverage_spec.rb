require "stringio"
require "timecop"

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

RSpec.describe "Per-test line coverage while Timecop freezes time" do
  let(:line_coverage) { Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage }
  let(:fixture_path) { File.expand_path("../rspec/fixtures/line_coverage/geometry.rb", __dir__) }
  let(:fixture_file) { Datadog::CI::Git::LocalRepository.relative_to_root(fixture_path) }

  before do
    skip "per-test line coverage is not supported on this Ruby" unless line_coverage.supported?
  end

  after do
    Timecop.return
    Timecop.mock_process_clock = false
    line_coverage.stop_collector
  end

  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:line_coverage_enabled) { true }
  end

  it "reports the lines of each test" do
    path = fixture_path
    with_new_rspec_environment do
      load path

      RSpec.describe "Square" do
        before(:context) do
          Timecop.freeze(Time.utc(1990))
          Timecop.mock_process_clock = true
        end

        it "computes the area" do
          expect(LineCoverageGeometry::Square.new(3).area).to eq(9)
        end

        it "describes itself" do
          expect(LineCoverageGeometry::Square.new(3).describe(:short)).to eq("square")
        end
      end

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
      ::RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)
    end

    expect(test_spans).to have(2).items
    expect(test_spans).to all(have_pass_status)

    expect(lines_of_test("computes the area")).to include(5, 6, 9, 10)
    expect(lines_of_test("describes itself")).to include(5, 6, 13, 16)
    expect(lines_of_test("describes itself")).not_to include(9)
  end

  def lines_of_test(name)
    span = test_spans.find { |test_span| test_span.get_tag("test.name").end_with?(name) }
    find_coverage_for_test(span)&.inspect_coverage&.fetch(fixture_file, nil)
  end
end
