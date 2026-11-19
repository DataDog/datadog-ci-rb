# frozen_string_literal: true

require "securerandom"
require_relative "utils/time"
require_relative "utils/encoding"

module Datadog
  module CI
    # An event owns its metadata and lifetime independently of the application tracer.
    class EventSpan
      attr_reader :id, :trace_id, :parent_id, :start_time, :end_time, :duration, :meta, :metrics
      attr_reader :name, :resource, :service, :type
      attr_accessor :status

      def initialize(name, trace_id:, parent_id: 0, service: nil, type: nil, resource: nil, tags: {}, &on_finish)
        @id = SecureRandom.random_number((1 << 63) - 1) + 1
        @trace_id = trace_id
        @parent_id = parent_id
        self.name = name
        self.resource = resource || name
        self.service = service
        self.type = type
        @status = 0
        @meta = {}
        @metrics = {}
        @start_time = Utils::Time.now.utc
        @started_at = Utils::Time.get_time
        @end_time = nil
        @duration = nil
        @on_finish = on_finish
        @finish_mutex = Mutex.new
        set_tags(tags)
      end

      def name=(value)
        @name = Utils.utf8_encode(value)
      end

      def resource=(value)
        @resource = value.nil? ? nil : Utils.utf8_encode(value)
      end

      def service=(value)
        @service = value.nil? ? nil : Utils.utf8_encode(value)
      end

      def type=(value)
        @type = value.nil? ? nil : Utils.utf8_encode(value)
      end

      def set_tag(key, value)
        key = key.to_s
        if value.is_a?(Numeric)
          set_metric(key, value)
        elsif !value.nil?
          @metrics.delete(key)
          @meta[key] = value.to_s
        end
      end

      def set_tags(tags)
        tags.each { |key, value| set_tag(key, value) }
      end

      def get_tag(key)
        @meta[key] || @metrics[key]
      end

      def clear_tag(key)
        @meta.delete(key)
        @metrics.delete(key)
      end

      def set_metric(key, value)
        return unless value.is_a?(Numeric)
        return if value.respond_to?(:finite?) && !value.finite?

        @meta.delete(key.to_s)
        @metrics[key.to_s] = value
      end

      def get_metric(key)
        @metrics[key]
      end

      def set_error(error)
        return if error.nil?

        @status = 1
        set_tag("error.type", error.class.name)
        set_tag("error.message", error.message)
        backtrace = error.backtrace
        set_tag("error.stack", backtrace.join("\n")) if backtrace
      end

      def finished?
        !@end_time.nil?
      end

      def finish(end_time = nil)
        callback = @finish_mutex.synchronize do
          next if finished?

          @end_time = end_time || Utils::Time.now.utc
          @duration = if end_time
            [end_time - @start_time, 0.0].max
          else
            [Utils::Time.get_time - @started_at, 0.0].max
          end
          @on_finish
        end
        callback&.call(self)
        self
      end
    end
  end
end
