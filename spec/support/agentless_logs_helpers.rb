require "datadog/ci"

module AgentlessLogsHelpers
  def agentless_logs
    @agentless_logs ||= fetch_agentless_logs
  end

  # Retrieves all traces in the current tracer instance.
  # This method does not cache its results.
  def fetch_agentless_logs
    runner.instance_variable_get(:@agentless_logs) || []
  end

  # Remove all traces from the current tracer instance and
  # busts cache of +#spans+ and +#span+.
  def clear_agentless_logs!
    runner.instance_variable_set(:@agentless_logs, [])

    @agentless_logs = nil
  end

  def setup_agentless_logs_writer!
    # DEV `*_any_instance_of` has concurrency issues when running with parallelism (e.g. JRuby).
    # DEV Single object `allow` and `expect` work as intended with parallelism.
    allow(Datadog::CI::Logs::Component).to receive(:new).and_wrap_original do |method, **args, &block|
      instance = method.call(**args, &block)

      write_lock = Mutex.new
      allow(instance).to receive(:write) do |event|
        instance.instance_exec do
          write_lock.synchronize do
            @agentless_logs ||= []
            @agentless_logs << event
          end
        end
      end

      instance
    end
  end

  def runner
    Datadog.send(:components).agentless_logs_submission
  end
end
