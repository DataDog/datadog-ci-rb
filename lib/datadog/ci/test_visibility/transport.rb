# frozen_string_literal: true

require "datadog/core/environment/identity"

require_relative "serializers/factories/test_level"
require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/event_platform_transport"

module Datadog
  module CI
    module TestVisibility
      class Transport < Datadog::CI::Transport::EventPlatformTransport
        attr_reader :serializers_factory, :dd_env

        def initialize(
          api:,
          dd_env:,
          serializers_factory: Datadog::CI::TestVisibility::Serializers::Factories::TestLevel,
          max_payload_size: DEFAULT_MAX_PAYLOAD_SIZE
        )
          super(api: api, max_payload_size: max_payload_size)

          @serializers_factory = serializers_factory
          @dd_env = dd_env
        end

        # this method is needed for compatibility with Datadog::Tracing::Writer that uses this Transport
        def send_traces(traces)
          send_events(traces)
        end

        private

        def telemetry_endpoint_tag
          Ext::Telemetry::Endpoint::TEST_CYCLE
        end

        def send_payload(encoded_payload)
          api.citestcycle_request(
            path: Datadog::CI::Ext::Transport::TEST_VISIBILITY_INTAKE_PATH,
            payload: encoded_payload
          )
        end

        def encode_events(traces)
          traces.flat_map do |trace|
            trace.spans.filter_map { |span| encode_span(trace, span) }
          end
        end

        def encode_span(trace, span)
          serializer = serializers_factory.serializer(trace, span, options: {itr_correlation_id: itr&.correlation_id})

          if serializer.valid?
            encoded = encoder.encode(serializer)

            if encoded.size > max_payload_size
              # This single event is too large, we can't flush it
              Datadog.logger.warn("Dropping test event. Payload too large: '#{span.inspect}'")
              Datadog.logger.warn(encoded)

              return nil
            end

            encoded
          else
            Datadog.logger.warn("Invalid event skipped: #{serializer} Errors: #{serializer.validation_errors}")
            nil
          end
        end

        def encoder
          Datadog::Core::Encoding::MsgpackEncoder
        end

        def write_payload_header(packer)
          packer.write_map_header(3) # Set header with how many elements in the map

          packer.write("version")
          packer.write(1)

          packer.write("metadata")
          packer.write_map_header(1)

          packer.write("*")
          metadata_fields_count = dd_env ? 4 : 3
          packer.write_map_header(metadata_fields_count)

          if dd_env
            packer.write("env")
            packer.write(dd_env)
          end

          packer.write("runtime-id")
          packer.write(Datadog::Core::Environment::Identity.id)

          packer.write("language")
          packer.write(Datadog::Core::Environment::Identity.lang)

          packer.write("library_version")
          packer.write(Datadog::CI::VERSION::STRING)

          packer.write("events")
        end

        def itr
          @test_optimisation ||= Datadog::CI.send(:test_optimisation)
        end
      end
    end
  end
end
