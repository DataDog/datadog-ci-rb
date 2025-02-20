# frozen_string_literal: true

require_relative "../contrib/instrumentation"
require_relative "../ext/app_types"
require_relative "../ext/environment"
require_relative "../ext/telemetry"
require_relative "../ext/test"
require_relative "../utils/telemetry"

module Datadog
  module CI
    module TestVisibility
      # Telemetry for test visibility
      module Telemetry
        SPAN_TYPE_TO_TELEMETRY_EVENT_TYPE = {
          Ext::AppTypes::TYPE_TEST => Ext::Telemetry::EventType::TEST,
          Ext::AppTypes::TYPE_TEST_SUITE => Ext::Telemetry::EventType::SUITE,
          Ext::AppTypes::TYPE_TEST_MODULE => Ext::Telemetry::EventType::MODULE,
          Ext::AppTypes::TYPE_TEST_SESSION => Ext::Telemetry::EventType::SESSION
        }.freeze

        def self.event_created(span)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_EVENT_CREATED, 1, event_tags_from_span(span))
        end

        def self.event_finished(span)
          tags = event_tags_from_span(span)
          add_browser_tags!(span, tags)
          Utils::Telemetry.inc(Ext::Telemetry::METRIC_EVENT_FINISHED, 1, tags)
        end

        def self.test_session_started(test_session)
          Utils::Telemetry.inc(
            Ext::Telemetry::METRIC_TEST_SESSION,
            1,
            {
              Ext::Telemetry::TAG_AUTO_INJECTED => Contrib::Instrumentation.auto_instrumented?.to_s,
              Ext::Telemetry::TAG_PROVIDER => test_session.ci_provider || Ext::Telemetry::Provider::UNSUPPORTED
            }
          )
        end

        def self.event_tags_from_span(span)
          # base tags for span
          # @type var tags: Hash[String, String]
          tags = {
            Ext::Telemetry::TAG_EVENT_TYPE => SPAN_TYPE_TO_TELEMETRY_EVENT_TYPE.fetch(span.type, "unknown"),
            Ext::Telemetry::TAG_TEST_FRAMEWORK => span.get_tag(Ext::Test::TAG_FRAMEWORK)
          }

          # ci provider tag
          tags[Ext::Telemetry::TAG_IS_UNSUPPORTED_CI] = "true" if span.get_tag(Ext::Environment::TAG_PROVIDER_NAME).nil?

          # codeowner tag
          tags[Ext::Telemetry::TAG_HAS_CODEOWNER] = "true" if span.get_tag(Ext::Test::TAG_CODEOWNERS)

          # set is_retry and retry_reason tags if span represents a retried test
          if span.get_tag(Ext::Test::TAG_IS_RETRY)
            tags[Ext::Telemetry::TAG_IS_RETRY] = "true"
            tags[Ext::Telemetry::TAG_RETRY_REASON] = span.get_tag(Ext::Test::TAG_RETRY_REASON)
          end

          # is_new
          tags[Ext::Telemetry::TAG_IS_NEW] = "true" if span.get_tag(Ext::Test::TAG_IS_NEW)

          # session-level tag - early_flake_detection_abort_reason
          early_flake_detection_abort_reason = span.get_tag(Ext::Test::TAG_EARLY_FLAKE_ABORT_REASON)
          if early_flake_detection_abort_reason
            tags[Ext::Telemetry::TAG_EARLY_FLAKE_DETECTION_ABORT_REASON] = early_flake_detection_abort_reason
          end

          # test management tags
          tags[Ext::Telemetry::TAG_IS_ATTEMPT_TO_FIX] = "true" if span.get_tag(Ext::Test::TAG_IS_ATTEMPT_TO_FIX)
          tags[Ext::Telemetry::TAG_IS_QUARANTINED] = "true" if span.get_tag(Ext::Test::TAG_IS_QUARANTINED)
          tags[Ext::Telemetry::TAG_IS_TEST_DISABLED] = "true" if span.get_tag(Ext::Test::TAG_IS_TEST_DISABLED)
          tags[Ext::Telemetry::TAG_HAS_FAILED_ALL_RETRIES] = "true" if span.get_tag(Ext::Test::TAG_HAS_FAILED_ALL_RETRIES)

          tags
        end

        def self.add_browser_tags!(span, tags)
          tags[Ext::Telemetry::TAG_IS_RUM] = "true" if span.get_tag(Ext::Test::TAG_IS_RUM_ACTIVE)
          browser_driver = span.get_tag(Ext::Test::TAG_BROWSER_DRIVER)
          tags[Ext::Telemetry::TAG_BROWSER_DRIVER] = browser_driver if browser_driver
        end
      end
    end
  end
end
