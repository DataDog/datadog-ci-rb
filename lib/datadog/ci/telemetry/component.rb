# frozen_string_literal: true

require "json"
require_relative "../utils/time"

module Datadog
  module CI
    module Telemetry
      # Aggregates CI telemetry without sharing the application tracer's runtime.
      class Component
        AGENTLESS_PATH = "/api/v2/apmtelemetry"
        AGENT_PATH = "/telemetry/proxy/api/v2/apmtelemetry"
        Metric = Struct.new(:namespace, :name, :type, :tags, :common, :timestamp, :values)

        def initialize(
          client:, logger:, application:, host:, runtime_id_provider:, agentless:,
          api_key: nil, enabled: true, aggregation_interval: 10.0,
          buffer_size: 10_000, shutdown_timeout: 5.0, debug: false
        )
          @client = client
          @logger = logger
          @application = application.dup.freeze
          @host = host.dup.freeze
          @runtime_id_provider = runtime_id_provider
          @path = agentless ? AGENTLESS_PATH : AGENT_PATH
          @api_key = agentless ? api_key : nil
          @enabled = enabled && (!agentless || !api_key.to_s.empty?)
          @aggregation_interval = aggregation_interval
          @buffer_size = buffer_size
          @shutdown_timeout = shutdown_timeout
          @debug = debug
          reset_process_state
        end

        def enabled?
          @enabled
        end

        alias_method :enabled, :enabled?

        def inc(namespace, metric_name, value, tags: {}, common: true)
          record(namespace, metric_name, value, tags, common, "count")
        end

        def distribution(namespace, metric_name, value, tags: {}, common: true)
          record(namespace, metric_name, value, tags, common, "distributions")
        end

        def flush
          return unless @enabled

          reset_process_state if @pid != Process.pid
          @send_mutex.synchronize do
            metrics = @mutex.synchronize do
              pending = @metrics.values
              @metrics = {}
              @buffered_values = 0
              @buffer_warning = false
              pending
            end
            return if metrics.empty?

            unless @started_event
              emit("app-started", {configuration: [], products: {}})
              @started_event = true
            end
            metrics.group_by { |metric| [metric.namespace, metric.type] }.each do |(namespace, type), series|
              emit(
                (type == "count") ? "generate-metrics" : "distributions",
                {namespace: namespace, series: series.map { |metric| serialize_metric(metric) }}
              )
            end
          end
          nil
        rescue => error
          @logger.warn("Failed to send Test Optimization telemetry: #{error}")
          nil
        end

        def disable!
          reset_process_state if @pid != Process.pid
          @mutex.synchronize do
            @enabled = false
            @metrics.clear
            @buffered_values = 0
            @condition.broadcast
          end
          nil
        end

        def shutdown!
          reset_process_state if @pid != Process.pid
          worker = @mutex.synchronize do
            return if @stopped

            @stopped = true
            @condition.broadcast
            @worker
          end
          if worker
            worker.join(@shutdown_timeout)
            @logger.warn("Test Optimization telemetry shutdown timed out.") if worker.alive?
          else
            flush
          end
          nil
        end

        private

        def record(namespace, name, value, tags, common, type)
          return unless @enabled
          return unless value.is_a?(Integer) || value.is_a?(Float)
          return if value.is_a?(Float) && !value.finite?

          reset_process_state if @pid != Process.pid
          normalized_tags = tags.is_a?(Array) ? tags.sort : tags.map { |key, item| "#{key}:#{item}" }.sort
          key = [namespace, name, type, normalized_tags, common]
          @mutex.synchronize do
            return if @stopped

            metric = @metrics[key]
            needs_space = metric.nil? || type == "distributions"
            if needs_space && @buffered_values >= @buffer_size
              unless @buffer_warning
                @logger.warn("Test Optimization telemetry buffer is full. Dropping a metric sample.")
                @buffer_warning = true
              end
              return
            end
            unless metric
              metric = Metric.new(namespace, name, type, normalized_tags, common, timestamp, [])
              @metrics[key] = metric
              @buffered_values += 1 if type == "count"
            end
            metric.timestamp = timestamp
            if type == "count"
              metric.values[0] = (metric.values[0] || 0) + value.to_i
            else
              metric.values << value
              @buffered_values += 1
            end
            start_worker unless @worker&.alive?
          end
          nil
        rescue => error
          @logger.warn("Failed to record Test Optimization telemetry: #{error}")
          nil
        end

        def serialize_metric(metric)
          # @type var result: Hash[Symbol, json_value]
          result = {metric: metric.name, tags: metric.tags, common: metric.common}
          if metric.type == "count"
            result[:points] = [[metric.timestamp, metric.values.first]]
            result[:type] = "count"
          else
            result[:points] = metric.values
          end
          result
        end

        def emit(request_type, payload)
          @sequence += 1
          runtime_id = @runtime_id_provider.call
          body = {
            api_version: "v2", application: @application, host: @host,
            runtime_id: runtime_id, seq_id: @sequence, tracer_time: timestamp,
            request_type: request_type, payload: payload, debug: @debug
          }
          headers = {
            "Content-Type" => "application/json",
            "DD-Telemetry-API-Version" => "v2",
            "DD-Telemetry-Request-Type" => request_type,
            "DD-Client-Library-Language" => "ruby",
            "DD-Client-Library-Version" => (@application[:tracer_version] || @application["tracer_version"]).to_s,
            "DD-Session-ID" => runtime_id,
            "DD-Internal-Untraced-Request" => "1"
          }
          api_key = @api_key
          headers["DD-API-KEY"] = api_key if api_key
          response = @client.call(path: @path, payload: JSON.generate(body), headers: headers, verb: "post")
          @logger.warn("Test Optimization telemetry request failed with HTTP #{response.code}.") unless response.ok?
          nil
        end

        def timestamp
          Utils::Time.now.to_i
        end

        def reset_process_state
          @pid = Process.pid
          @mutex = Mutex.new
          @send_mutex = Mutex.new
          @condition = ConditionVariable.new
          @metrics = {}
          @buffered_values = 0
          @buffer_warning = false
          @sequence = 0
          @started_event = false
          @stopped = false
          @worker = nil
        end

        def start_worker
          worker = Thread.new do
            loop do
              stopped = @mutex.synchronize do
                @condition.wait(@mutex, @aggregation_interval) unless @stopped || !@enabled
                @stopped || !@enabled
              end
              flush
              break if stopped
            end
            @send_mutex.synchronize { emit("app-closing", {}) } if @enabled && @started_event
          rescue => error
            @logger.warn("Test Optimization telemetry worker failed: #{error}")
          end
          worker.name = "datadog-ci-telemetry" if worker.respond_to?(:name=)
          @worker = worker
        end
      end
    end
  end
end
