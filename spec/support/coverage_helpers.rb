require "datadog/ci"

module CoverageHelpers
  # Existing assertions describe per-test/per-suite attribution. Session
  # dependencies are exposed separately so they cannot hide cross-test leaks.
  def coverage_events
    fetch_coverage_events.reject { |event| event.test_suite_id.nil? }
  end

  def session_coverage_events
    fetch_coverage_events.select { |event| event.test_suite_id.nil? }
  end

  def find_coverage_for_test(test_span)
    coverage_events.find { |event| event.test_id == test_span.id.to_s }
  end

  def fetch_coverage_events
    @captured_coverage_events || []
  end

  def clear_coverage_events!
    @captured_coverage_events&.clear
  end

  def setup_test_coverage_writer!
    @captured_coverage_events = []
    events = @captured_coverage_events
    write_lock = Mutex.new
    writer = instance_double(Datadog::CI::AsyncWriter, stop: nil)
    allow(writer).to receive(:write) { |event| write_lock.synchronize { events << event } }
    allow(Datadog::CI::TestImpactAnalysis::Component).to receive(:new).and_wrap_original do |method, **args|
      method.call(**args.merge(coverage_writer: writer))
    end
  end

  def test_impact_analysis_component
    Datadog::CI.send(:test_impact_analysis)
  end

  def expect_coverage_events_belong_to_session(test_session_span)
    expect(coverage_events.map(&:test_session_id)).to all eq(test_session_span.id.to_s)
  end

  def expect_coverage_events_belong_to_suite(test_suite_span)
    expect(coverage_events.map(&:test_suite_id)).to all eq(test_suite_span.id.to_s)
  end

  def expect_coverage_events_belong_to_suites(test_suite_spans)
    expect(coverage_events.map(&:test_suite_id).sort.uniq).to eq(test_suite_spans.map(&:id).map(&:to_s).sort.uniq)
  end

  def expect_coverage_events_belong_to_tests(test_spans)
    expect(coverage_events.map(&:test_id).sort).to eq(test_spans.map(&:id).map(&:to_s).sort)
  end

  def expect_non_empty_coverages
    expect(coverage_events.map(&:inspect_coverage).map(&:size)).to all be > 0
  end
end
