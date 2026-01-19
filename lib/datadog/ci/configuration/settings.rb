# frozen_string_literal: true

require_relative "../contrib/instrumentation"
require_relative "../ext/settings"
require_relative "../utils/bundle"
require_relative "../utils/parsing"

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to ddtrace settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :ci do
              option :enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_ENABLED
                o.default do
                  env_value = DATADOG_ENV[CI::Ext::Settings::ENV_MODE_ENABLED]
                  if env_value && !DATADOG_ENV[CI::Ext::Settings::ENV_ENABLED]
                    Datadog::Core.log_deprecation do
                      "#{CI::Ext::Settings::ENV_MODE_ENABLED} environment variable is deprecated, " \
                        "use #{CI::Ext::Settings::ENV_ENABLED} instead."
                    end
                    Utils::Parsing.convert_to_bool(env_value)
                  else
                    false
                  end
                end
              end

              option :test_session_name do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_TEST_SESSION_NAME
              end

              option :agentless_mode_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_AGENTLESS_MODE_ENABLED
                o.default false
              end

              option :agentless_url do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_AGENTLESS_URL
              end

              option :force_test_level_visibility do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_FORCE_TEST_LEVEL_VISIBILITY
                o.default false
              end

              option :experimental_test_suite_level_visibility_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_EXPERIMENTAL_TEST_SUITE_LEVEL_VISIBILITY_ENABLED
                o.default false
                o.after_set do |value|
                  if value
                    Datadog::Core.log_deprecation do
                      "The experimental_test_suite_level_visibility_enabled setting has no effect and will be removed in 2.0. " \
                        "Test suite level visibility is now enabled by default. " \
                        "If you want to disable test suite level visibility set configuration.ci.force_test_level_visibility = true."
                    end
                  end
                end
              end

              option :itr_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_ITR_ENABLED
                o.default true
              end

              option :git_metadata_upload_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_GIT_METADATA_UPLOAD_ENABLED
                o.default true
              end

              option :itr_code_coverage_excluded_bundle_path do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_ITR_CODE_COVERAGE_EXCLUDED_BUNDLE_PATH
                o.default do
                  Datadog::CI::Utils::Bundle.location
                end
              end

              option :itr_code_coverage_use_single_threaded_mode do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_ITR_CODE_COVERAGE_USE_SINGLE_THREADED_MODE
                o.default false
              end

              option :itr_test_impact_analysis_use_allocation_tracing do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_ITR_TEST_IMPACT_ANALYSIS_USE_ALLOCATION_TRACING
                o.default true
              end

              option :retry_failed_tests_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_ENABLED
                o.default true
              end

              option :retry_failed_tests_max_attempts do |o|
                o.type :int
                o.env CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_MAX_ATTEMPTS
                o.default 5
              end

              option :retry_failed_tests_total_limit do |o|
                o.type :int
                o.env CI::Ext::Settings::ENV_RETRY_FAILED_TESTS_TOTAL_LIMIT
                o.default 1000
              end

              option :retry_new_tests_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_RETRY_NEW_TESTS_ENABLED
                o.default true
              end

              option :test_management_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_TEST_MANAGEMENT_ENABLED
                o.default true
              end

              option :test_management_attempt_to_fix_retries_count do |o|
                o.type :int
                o.env CI::Ext::Settings::ENV_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES
                o.default 20
              end

              option :agentless_logs_submission_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_AGENTLESS_LOGS_SUBMISSION_ENABLED
                o.default false
              end

              option :agentless_logs_submission_url do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_AGENTLESS_LOGS_SUBMISSION_URL
              end

              # internal only
              option :discard_traces do |o|
                o.type :bool
                o.default false
              end

              # internal only
              option :test_visibility_drb_server_uri do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_TEST_VISIBILITY_DRB_SERVER_URI
              end

              option :impacted_tests_detection_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_IMPACTED_TESTS_DETECTION_ENABLED
                o.default false
              end

              option :test_discovery_enabled do |o|
                o.type :bool
                o.env Ext::Settings::ENV_TEST_DISCOVERY_MODE_ENABLED
                o.default false
              end

              option :test_discovery_output_path do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_TEST_DISCOVERY_OUTPUT_PATH
              end

              option :tia_static_dependencies_tracking_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_TIA_STATIC_DEPENDENCIES_TRACKING_ENABLED
                o.default false
              end

              option :code_coverage_report_upload_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_CODE_COVERAGE_REPORT_UPLOAD_ENABLED
                o.default true
              end

              define_method(:instrument) do |integration_name, options = {}, &block|
                return unless enabled

                Contrib::Instrumentation.instrument(integration_name, options, &block)
              end

              define_method(:[]) do |integration_name|
                Contrib::Instrumentation.fetch_integration(integration_name).configuration
              end

              option :trace_flush

              option :writer_options do |o|
                o.type :hash
                o.default({})
              end
            end
          end
        end
      end
    end
  end
end
