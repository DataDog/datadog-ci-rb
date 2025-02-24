# frozen_string_literal: true

require "datadog/core/environment/identity"
require "datadog/core/telemetry/logging"
require "datadog/core/utils/only_once"

require_relative "capabilities"
require_relative "serializers/factories/test_level"

require_relative "../ext/app_types"
require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/event_platform_transport"
require_relative "../transport/telemetry"

module Datadog
  module CI
    module TestVisibility
      class Transport < Datadog::CI::Transport::EventPlatformTransport
        attr_reader :serializers_factory, :dd_env

        def self.log_once
          @log_once ||= Datadog::Core::Utils::OnlyOnce.new
        end

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
          serializer = serializers_factory.serializer(
            trace,
            span,
            options: {itr_correlation_id: test_optimisation&.correlation_id}
          )

          if serializer.valid?
            encoded = encoder.encode(serializer)
            return nil if event_too_large?(span, encoded)

            encoded
          else
            message = "Invalid event skipped: #{serializer} Errors: #{serializer.validation_errors}"
            Datadog.logger.warn(message)
            CI::Transport::Telemetry.endpoint_payload_dropped(1, endpoint: telemetry_endpoint_tag)

            # log invalid message once as error to internal telemetry
            self.class.log_once.run do
              Core::Telemetry::Logger.error(message)
            end

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
          packer.write_map_header(1 + Ext::AppTypes::CI_SPAN_TYPES.size)

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

          library_capabilities_tags = Capabilities.tags

          Ext::AppTypes::CI_SPAN_TYPES.each do |ci_span_type|
            packer.write(ci_span_type)
            packer.write_map_header(1 + library_capabilities_tags.count)

            packer.write(Ext::Test::METADATA_TAG_TEST_SESSION_NAME)
            packer.write(test_visibility&.logical_test_session_name)

            library_capabilities_tags.each do |tag, value|
              packer.write(tag)
              packer.write(value)
            end
          end

          packer.write("events")
        end

        def test_optimisation
          @test_optimisation ||= Datadog::CI.send(:test_optimisation)
        end

        def test_visibility
          @test_visibility ||= Datadog::CI.send(:test_visibility)
        end
      end
    end
  end
end
