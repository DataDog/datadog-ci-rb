# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "CI timing with Timecop loaded first" do
  it "keeps event timing and telemetry timestamps outside frozen application time" do
    script = <<~RUBY
      require "timecop"
      Timecop.mock_process_clock = true
      require "datadog/ci/event_span"
      require "datadog/ci/telemetry/component"
      require "logger"

      class TelemetryCapture
        attr_reader :requests
        def initialize
          @requests = []
        end
        def call(**request)
          @requests << JSON.parse(request[:payload])
          Struct.new(:ok?).new(true)
        end
      end

      Timecop.freeze(Time.utc(1990)) do
        span = Datadog::CI::EventSpan.new("example", trace_id: 1)
        sleep 0.001
        span.finish
        abort "frozen event timestamp" if span.start_time.year == 1990
        abort "frozen event duration" unless span.duration > 0

        client = TelemetryCapture.new
        telemetry = Datadog::CI::Telemetry::Component.new(
          client: client, logger: Logger.new(File::NULL),
          application: {}, host: {}, runtime_id_provider: -> { "runtime" },
          agentless: false, aggregation_interval: 60.0
        )
        telemetry.inc("civisibility", "events", 1)
        telemetry.shutdown!
        abort "missing telemetry" if client.requests.empty?
        abort "frozen telemetry timestamp" unless client.requests.all? { |request| request["tracer_time"] > Time.utc(2020).to_i }
      end
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)
    expect(status.success?).to be(true), output
  end
end
