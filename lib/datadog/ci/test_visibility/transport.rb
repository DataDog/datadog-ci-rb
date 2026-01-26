# frozen_string_literal: true

require "datadog/core/environment/identity"
require "datadog/core/telemetry/logging"
require "datadog/core/utils/only_once"

require_relative "serializers/factories/test_level"

require_relative "../ext/app_types"
require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/event_platform_transport"
require_relative "../transport/telemetry"
require_relative "../utils/configuration"

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
          serializer = serializers_factory.serializer(
            trace,
            span,
            options: {itr_correlation_id: test_impact_analysis&.correlation_id}
          )

          if serializer.valid?
            encoded = encoder.encode(serializer)
            return nil if event_too_large?(span, encoded)

            encoded
          else
            message = "Event with type #{serializer.event_type}(name=#{serializer.name}) is invalid: #{serializer.validation_errors}"

            if serializer.event_type == "span"
              # events of type span are often skipped because of missing resource field
              # (because they are misconfigured in tests context)
              Datadog.logger.debug(message)
            else
              Datadog.logger.warn(message)
              CI::Transport::Telemetry.endpoint_payload_dropped(1, endpoint: telemetry_endpoint_tag)

              # for CI events log all events to internal telemetry
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

          library_capabilities_tags = Ext::Test::LibraryCapabilities::CAPABILITY_VERSIONS

          Ext::AppTypes::CI_SPAN_TYPES.each do |ci_span_type|
            packer.write(ci_span_type)
            packer.write_map_header(2 + library_capabilities_tags.count)

            packer.write(Ext::Test::TAG_TEST_SESSION_NAME)
            packer.write(test_visibility&.logical_test_session_name)

            packer.write(Ext::Test::TAG_USER_PROVIDED_TEST_SERVICE)
            packer.write(Utils::Configuration.service_name_provided_by_user?.to_s)

            library_capabilities_tags.each do |tag, value|
              packer.write(tag)
              packer.write(value)
            end
          end

          packer.write("events")
        end

        def test_impact_analysis
          @test_impact_analysis ||= Datadog::CI.send(:test_impact_analysis)
        end

        def test_visibility
          @test_visibility ||= Datadog::CI.send(:test_visibility)
        end
      end
    end
  end
end
