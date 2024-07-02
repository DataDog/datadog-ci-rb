require "datadog/ci"

module CoverageHelpers
  def coverage_events
    @coverage_events ||= fetch_coverage_events
  end

  def find_coverage_for_test(test_span)
    coverage_events.find { |event| event.test_id == test_span.id.to_s }
  end

  # Retrieves all traces in the current tracer instance.
  # This method does not cache its results.
  def fetch_coverage_events
    runner.instance_variable_get(:@coverage_events) || []
  end

  # Remove all traces from the current tracer instance and
  # busts cache of +#spans+ and +#span+.
  def clear_coverage_events!
    runner.instance_variable_set(:@coverage_events, [])

    @coverage_events = nil
  end

  def setup_test_coverage_writer!
    # DEV `*_any_instance_of` has concurrency issues when running with parallelism (e.g. JRuby).
    # DEV Single object `allow` and `expect` work as intended with parallelism.
    allow(Datadog::CI::TestOptimisation::Component).to receive(:new).and_wrap_original do |method, **args, &block|
      instance = method.call(**args, &block)

      write_lock = Mutex.new
      allow(instance).to receive(:write) do |event|
        instance.instance_exec do
          write_lock.synchronize do
            @coverage_events ||= []
            @coverage_events << event
          end
        end
      end

      instance
    end
  end

  def runner
    Datadog::CI.send(:test_optimisation)
  end

  def expect_coverage_events_belong_to_session(test_session_span)
    expect(coverage_events.map(&:test_session_id)).to all eq(test_session_span.id.to_s)
  end

  def expect_coverage_events_belong_to_suite(test_suite_span)
    expect(coverage_events.map(&:test_suite_id)).to all eq(test_suite_span.id.to_s)
  end

  def expect_coverage_events_belong_to_suites(test_suite_spans)
    expect(coverage_events.map(&:test_suite_id).sort).to eq(test_suite_spans.map(&:id).map(&:to_s).sort)
  end

  def expect_coverage_events_belong_to_tests(test_spans)
    expect(coverage_events.map(&:test_id).sort).to eq(test_spans.map(&:id).map(&:to_s).sort)
  end

  def expect_non_empty_coverages
    expect(coverage_events.map(&:coverage).map(&:size)).to all be > 0
  end
end
