require "datadog/ci"

module AgentlessLogsHelpers
  def agentless_logs
    @agentless_logs ||= fetch_agentless_logs
  end

  def fetch_agentless_logs
    @recorded_agentless_logs&.fetch(agentless_logs_component, []) || []
  end

  def clear_agentless_logs!
    @recorded_agentless_logs&.each_value(&:clear)
    @agentless_logs = nil
  end

  def setup_agentless_logs_writer!
    @recorded_agentless_logs = {}
    allow(Datadog::CI::Logs::Component).to receive(:new).and_wrap_original do |method, **args, &block|
      instance = method.call(**args, &block)
      events = []
      @recorded_agentless_logs[instance] = events
      write_lock = Mutex.new
      allow(instance).to receive(:write) do |event|
        write_lock.synchronize { events << event }
      end
      instance
    end
  end

  def agentless_logs_component
    Datadog::CI.components.agentless_logs_submission
  end
end
