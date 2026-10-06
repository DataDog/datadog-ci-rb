# frozen_string_literal: true

require "datadog/core/environment/identity"
require "datadog/core/telemetry/logging"
require "datadog/core/utils/only_once"

require_relative "serializers/factories/test_suite_level"
require_relative "serializers/meta_truncation"

require_relative "../ext/app_types"
require_relative "../ext/environment"
require_relative "../ext/git"
require_relative "../ext/telemetry"
require_relative "../ext/transport"
require_relative "../transport/event_platform_transport"
require_relative "../transport/telemetry"
require_relative "../utils/configuration"

module Datadog
  module CI
    module TestTracing
      class Transport < Datadog::CI::Transport::EventPlatformTransport
        # Explicitly allowlist environment fields; custom ci.* and git.* tags belong to individual events.
        SHARED_ENVIRONMENT_TAGS = [
          Ext::Environment::TAG_JOB_ID,
          Ext::Environment::TAG_JOB_NAME,
          Ext::Environment::TAG_JOB_URL,
          Ext::Environment::TAG_NODE_LABELS,
          Ext::Environment::TAG_NODE_NAME,
          Ext::Environment::TAG_PIPELINE_ID,
          Ext::Environment::TAG_PIPELINE_NAME,
          Ext::Environment::TAG_PIPELINE_DISPLAY_NAME,
          Ext::Environment::TAG_PIPELINE_NUMBER,
          Ext::Environment::TAG_PIPELINE_URL,
          Ext::Environment::TAG_PROVIDER_NAME,
          Ext::Environment::TAG_STAGE_NAME,
          Ext::Environment::TAG_WORKSPACE_PATH,
          Ext::Git::TAG_BRANCH,
          Ext::Git::TAG_TAG,
          Ext::Git::TAG_REPOSITORY_URL,
          Ext::Git::TAG_COMMIT_SHA,
          Ext::Git::TAG_COMMIT_MESSAGE,
          Ext::Git::TAG_COMMIT_AUTHOR_NAME,
          Ext::Git::TAG_COMMIT_AUTHOR_EMAIL,
          Ext::Git::TAG_COMMIT_AUTHOR_DATE,
          Ext::Git::TAG_COMMIT_COMMITTER_NAME,
          Ext::Git::TAG_COMMIT_COMMITTER_EMAIL,
          Ext::Git::TAG_COMMIT_COMMITTER_DATE,
          Ext::Git::TAG_COMMIT_HEAD_SHA,
          Ext::Git::TAG_COMMIT_HEAD_MESSAGE,
          Ext::Git::TAG_COMMIT_HEAD_AUTHOR_NAME,
          Ext::Git::TAG_COMMIT_HEAD_AUTHOR_EMAIL,
          Ext::Git::TAG_COMMIT_HEAD_AUTHOR_DATE,
          Ext::Git::TAG_COMMIT_HEAD_COMMITTER_NAME,
          Ext::Git::TAG_COMMIT_HEAD_COMMITTER_EMAIL,
          Ext::Git::TAG_COMMIT_HEAD_COMMITTER_DATE,
          Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH,
          Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH_SHA,
          Ext::Git::TAG_PULL_REQUEST_BASE_BRANCH_HEAD_SHA
        ].freeze

        attr_reader :dd_env

        def initialize(
          api:,
          dd_env:,
          max_payload_size: DEFAULT_MAX_PAYLOAD_SIZE
        )
          super(api: api, max_payload_size: max_payload_size)

          @dd_env = dd_env
          @send_mutex = Mutex.new
          @test_level_metadata = {}
        end

        def send_events(events)
          # Keep one metadata snapshot for serialization and every split payload, even if callers flush concurrently.
          @send_mutex.synchronize do
            @test_level_metadata = build_test_level_metadata
            super
          end
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
          serializer = Serializers::Factories::TestSuiteLevel.serializer(
            trace,
            span,
            options: {itr_correlation_id: test_impact_analysis&.correlation_id, test_level_metadata: @test_level_metadata}
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
          packer.write_map_header(2)

          packer.write("*")
          metadata_fields_count = dd_env ? 4 : 3
          packer.write_map_header(metadata_fields_count)

          if dd_env
            packer.write("env")
            packer.write(Serializers::MetaTruncation.truncate_value(dd_env))
          end

          packer.write("runtime-id")
          packer.write(Serializers::MetaTruncation.truncate_value(Datadog::Core::Environment::Identity.id))

          packer.write("language")
          packer.write(Serializers::MetaTruncation.truncate_value(Datadog::Core::Environment::Identity.lang))

          packer.write("library_version")
          packer.write(Serializers::MetaTruncation.truncate_value(Datadog::CI::VERSION::STRING))

          packer.write("test_levels")
          packer.write(@test_level_metadata)

          packer.write("events")
        end

        def build_test_level_metadata
          environment_tags = test_tracing&.environment_tags || {}
          shared_tags = environment_tags.slice(*SHARED_ENVIRONMENT_TAGS)
          session_name = test_tracing&.logical_test_session_name
          shared_tags[Ext::Test::TAG_TEST_SESSION_NAME] = session_name unless session_name.nil?
          shared_tags[Ext::Test::TAG_USER_PROVIDED_TEST_SERVICE] = Utils::Configuration.service_name_provided_by_user?.to_s
          shared_tags.merge!(Ext::Test::LibraryCapabilities::CAPABILITY_VERSIONS)

          Serializers::MetaTruncation.truncate_string_values(shared_tags)
        end

        def test_impact_analysis
          @test_impact_analysis ||= Datadog::CI.send(:test_impact_analysis)
        end

        def test_tracing
          @test_tracing ||= Datadog::CI.send(:test_tracing)
        end
      end
    end
  end
end
