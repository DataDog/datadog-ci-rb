require "stringio"

require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

RSpec.describe "RSpec instrumentation with per-test line coverage started before Datadog is configured" do
  let(:line_coverage) { Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage }
  # No other spec loads this file, so its initialiser lines run only while this spec loads it.
  let(:fixture_path) { File.join(__dir__, "fixtures/line_coverage/early_start.rb") }
  let(:fixture_file) { Datadog::CI::Git::LocalRepository.relative_to_root(fixture_path) }

  # Runs before the configuration of the "CI mode activated" context below, as auto
  # instrumentation does when the code under test loads before the test framework.
  before do
    skip "per-test line coverage is not supported on this Ruby" unless line_coverage.supported?

    line_coverage.stop_collector
    settings = double("settings", ci: double("ci settings", tia_line_coverage_enabled: true, itr_enabled: true))
    Datadog::CI::TestImpactAnalysis::Component.start_line_coverage_before_configure(settings)
    load fixture_path
  end

  after do
    line_coverage.stop_collector
  end

  include_context "CI mode activated" do
    let(:integration_name) { :rspec }
    let(:itr_enabled) { true }
    let(:code_coverage_enabled) { true }
    let(:line_coverage_enabled) { true }
    # The default, which the start before configuration also uses.
    let(:bundle_path) { Datadog::CI::Utils::Bundle.location }
  end

  def run_rspec
    with_new_rspec_environment do
      yield

      options = ::RSpec::Core::ConfigurationOptions.new(%w[--pattern none])
      ::RSpec::Core::Runner.new(options).run(StringIO.new, StringIO.new)
    end
  end

  it "credits to a test the initialiser lines of a file that loaded before configuration" do
    run_rspec do
      RSpec.describe "Early start" do
        it "reads the answer" do
          expect(LineCoverageEarlyStart.answer).to eq(42)
        end
      end
    end

    expect(test_spans).to have(1).item
    expect(first_test_span).to have_pass_status
    # Initialiser lines 2, 3, 5 and 8, and the test's own lines 6 and 7.
    expect(find_coverage_for_test(first_test_span).inspect_coverage.fetch(fixture_file)).to eq([2, 3, 5, 6, 7, 8])
  end

  it "collects the processes that tests start only once the test session collects line coverage" do
    child_processes = Datadog::CI::TestImpactAnalysis::Coverage::ChildProcesses
    collected_before_session = !child_processes.current.nil?
    collected_in_test = nil

    run_rspec do
      RSpec.describe "Early start" do
        it "runs in the session" do
          collected_in_test = !child_processes.current.nil?
        end
      end
    end

    expect(first_test_span).to have_pass_status
    expect([collected_before_session, collected_in_test]).to eq([false, true])
  end
end
