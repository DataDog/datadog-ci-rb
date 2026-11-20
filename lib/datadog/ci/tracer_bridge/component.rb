# frozen_string_literal: true

module Datadog
  module CI
    module TracerBridge
      # Routes application spans without sharing the tracer lifecycle with CI.
      class Component
        # Keep tracer telemetry outside WebMock without changing its configuration.
        def self.activate_telemetry_compatibility!
          if defined?(::Datadog::Core::Telemetry::Transport::HTTP)
            ::Datadog::Core::Telemetry::Transport::HTTP.singleton_class.prepend(TelemetryTransport)
          end
          if defined?(::Datadog::Core::Telemetry::Http::Adapters::Net)
            ::Datadog::Core::Telemetry::Http::Adapters::Net.prepend(TelemetryAdapter)
          end
        end

        module TelemetryTransport
          def agentless_telemetry(agent_settings:, logger:, api_key: nil, headers: nil)
            super do |builder|
              yield(builder) if block_given?
              adapter = builder.default_adapter
              adapter.extend(TelemetryAdapter) if adapter.instance_of?(::Datadog::Core::Transport::HTTP::Adapters::Net)
            end
          end

          def agent_telemetry(agent_settings:, logger:, headers: nil)
            super do |builder|
              yield(builder) if block_given?
              adapter = builder.default_adapter
              adapter.extend(TelemetryAdapter) if adapter.instance_of?(::Datadog::Core::Transport::HTTP::Adapters::Net)
            end
          end
        end
        private_constant :TelemetryTransport

        module TelemetryAdapter
          def open(&block)
            return super unless defined?(::WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP)

            connection = ::WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP.new(@hostname, @port, nil)
            connection.use_ssl = @ssl
            connection.open_timeout = connection.read_timeout = @timeout
            connection.start(&block)
          end
        end
        private_constant :TelemetryAdapter

        CONTEXT_KEY = :datadog_ci_tracer_bridge_scopes
        SESSION_CONTEXT_KEY = :datadog_ci_tracer_bridge_session_scope
        ORIGIN = "ciapp-test"

        class Scope
          attr_reader :owner, :span, :contexts

          def initialize(owner, span, contexts)
            @owner = owner
            @span = span
            @contexts = contexts
          end
        end

        class SavedContext
          attr_reader :context, :previous_trace
          attr_accessor :trace

          def initialize(context, previous_trace, trace)
            @context = context
            @previous_trace = previous_trace
            @trace = trace
          end
        end
        private_constant :Scope, :SavedContext

        def initialize(writer:, logger:, enabled: true)
          @writer = writer
          @logger = logger
          @enabled = enabled
          @session = nil
        end

        def on_session_started(session)
          return unless @enabled

          @session = session
        end

        def on_session_finished(session)
          return unless @session.equal?(session)

          # Keep routing delayed spans until the owning CI runtime shuts down.
          @session = nil
          restore_session_scope
        end

        def on_test_started(test)
          on_span_started(test)
        end

        def on_test_finished(test)
          on_span_finished(test)
        end

        def on_span_started(span)
          return unless @enabled

          scopes << Scope.new(self, span, [])
        end

        def on_span_finished(span)
          current = scopes
          return unless current.any? { |scope| scope.owner.equal?(self) && scope.span.equal?(span) }

          while (scope = current.pop)
            restore_scope(scope)
            break if scope.span.equal?(span)
          end
          Thread.current[CONTEXT_KEY] = nil if current.empty?
        rescue => error
          warn_failure("restore application trace context", error)
        end

        def observe(tracer)
          return unless @enabled

          wrap_writer(tracer)
          scope = active_scope
          unless scope
            restore_session_scope
            return
          end

          context = tracer.provider.context
          saved = scope.contexts.find { |candidate| candidate.context.equal?(context) }
          if saved
            return if context.active_trace.equal?(saved.trace) && !saved.trace.finished?
            return if context.active_trace && !context.active_trace.equal?(saved.previous_trace)
          end

          previous = saved ? saved.previous_trace : context.active_trace
          digest = ::Datadog::Tracing::TraceDigest.new(
            trace_id: scope.span.trace_id,
            span_id: scope.span.id,
            trace_origin: ORIGIN,
            trace_sampling_priority: 1
          )
          trace = tracer.continue_trace!(digest)
          if saved
            saved.trace = trace
          else
            scope.contexts << SavedContext.new(context, previous, trace)
          end
        rescue => error
          warn_failure("attach application tracer", error)
        end

        def write(trace)
          return false unless @enabled

          @writer.write(trace)
          true
        rescue => error
          warn_failure("send application spans", error)
          true
        end

        def shutdown!
          @enabled = false
          @session = nil
          restore_session_scope
          current = scopes
          current.reverse_each { |scope| restore_scope(scope) if scope.owner.equal?(self) }
          current.reject! { |scope| scope.owner.equal?(self) }
          Thread.current[CONTEXT_KEY] = nil if current.empty?
        end

        private

        def scopes
          Thread.current[CONTEXT_KEY] ||= []
        end

        def active_scope
          scope = scopes.reverse.find { |candidate| candidate.owner.equal?(self) }
          return scope if scope
          session = @session
          return unless session

          existing = Thread.current[SESSION_CONTEXT_KEY]
          return existing if existing && existing.owner.equal?(self) && existing.span.equal?(session)

          restore_session_scope
          Thread.current[SESSION_CONTEXT_KEY] = Scope.new(self, session, [])
        end

        def wrap_writer(tracer)
          original = tracer.writer
          return if original.is_a?(Writer) && original.bridge.equal?(self)

          original = original.delegate while original.is_a?(Writer)
          tracer.writer = Writer.new(original, self)
        end

        def restore_session_scope
          scope = Thread.current[SESSION_CONTEXT_KEY]
          return unless scope && scope.owner.equal?(self)

          restore_scope(scope)
          Thread.current[SESSION_CONTEXT_KEY] = nil
        end

        def restore_scope(scope)
          scope.contexts.reverse_each do |saved|
            active = saved.context.active_trace
            next unless active.equal?(saved.trace) || active.nil?
            next if active.nil? && !saved.trace.finished?

            saved.context.activate!(saved.previous_trace)
          end
          scope.contexts.clear
        end

        def warn_failure(action, error)
          @logger.warn("Failed to #{action}: #{error.class}: #{error.message}")
        rescue
          nil
        end

        # The original writer owns its workers. CI owns its separate writer.
        class Writer
          attr_reader :delegate, :bridge

          def initialize(delegate, bridge)
            @delegate = delegate
            @bridge = bridge
          end

          def write(trace)
            @delegate.write(trace) unless @bridge.write(trace)
          end

          def stop
            @delegate.stop
          end

          def method_missing(name, *args, **kwargs, &block)
            return super unless @delegate.respond_to?(name)

            @delegate.public_send(name, *args, **kwargs, &block)
          end

          def respond_to_missing?(name, include_private = false)
            @delegate.respond_to?(name, include_private) || super
          end
        end
        private_constant :Writer
      end
    end
  end
end
