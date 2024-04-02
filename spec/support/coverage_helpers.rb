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
    allow(Datadog::CI::ITR::Runner).to receive(:new).and_wrap_original do |method, **args, &block|
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
    Datadog::CI.send(:itr_runner)
  end
end
