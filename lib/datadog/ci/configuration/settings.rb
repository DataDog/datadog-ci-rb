# frozen_string_literal: true

require "logger"

require_relative "base"
require_relative "../contrib/instrumentation"
require_relative "../ext/settings"
require_relative "../ext/test"
require_relative "../ext/git"
require_relative "../ext/test_optimization_cache"
require_relative "../utils/bundle"
require_relative "../utils/configuration"
require_relative "../utils/parsing"

module Datadog
  module CI
    module Configuration
      def self.environment
        ::ENV
      end

      # Defines the settings shared by manual and automatic instrumentation.
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
                  env_value = environment[CI::Ext::Settings::ENV_MODE_ENABLED]
                  if env_value && !environment[CI::Ext::Settings::ENV_ENABLED]
                    Datadog::CI.logger.warn do
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
                o.after_set do |value|
                  if value
                    Datadog::CI.logger.warn do
                      "The force_test_level_visibility setting has no effect because test-level visibility is no longer supported."
                    end
                  end
                end
              end

              option :experimental_test_suite_level_visibility_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_EXPERIMENTAL_TEST_SUITE_LEVEL_VISIBILITY_ENABLED
                o.default false
                o.after_set do |value|
                  if value
                    Datadog::CI.logger.warn do
                      "The experimental_test_suite_level_visibility_enabled setting has no effect and will be removed in 2.0. " \
                        "Test suite level visibility is always enabled."
                    end
                  end
                end
              end

              option :trace_setup_teardown_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_TRACE_SETUP_TEARDOWN_ENABLED
                o.default false
              end

              option :itr_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_ITR_ENABLED
                o.default true
              end

              option :tia_test_skipping_mode do |o|
                o.type :string
                o.env CI::Ext::Settings::ENV_TIA_TEST_SKIPPING_MODE
                o.default CI::Ext::Test::TIATestSkippingMode::TEST
                o.setter do |mode|
                  Utils::Configuration.normalize_tia_test_skipping_mode(mode)
                end
              end

              option :git_pull_request_base_branch do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Git::ENV_PULL_REQUEST_BASE_BRANCH
                o.setter { |value| value unless value.nil? || value.strip.empty? }
              end

              option :git_pull_request_base_branch_sha do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Git::ENV_PULL_REQUEST_BASE_BRANCH_SHA
                o.setter { |value| value unless value.nil? || value.strip.empty? }
              end

              option :git_commit_head_sha do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Git::ENV_COMMIT_HEAD_SHA
                o.setter { |value| value unless value.nil? || value.strip.empty? }
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
                o.setter { |value| (value >= 0) ? value : 5 }
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

              option :dynamic_atr_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_DYNAMIC_ATR_ENABLED
                o.default false
              end

              option :dynamic_atr_buckets do |o|
                o.type :array, nilable: true
                o.env CI::Ext::Settings::ENV_DYNAMIC_ATR_BUCKETS
                o.setter do |values|
                  if values.nil? || values.empty?
                    nil
                  else
                    buckets = values.map do |value|
                      normalized = value.to_s.strip
                      normalized.to_i if normalized.match?(/\A\d+\z/)
                    end

                    if buckets.length == 5 && buckets.all? { |value| value&.between?(1, 20) }
                      buckets
                    else
                      Datadog::CI.logger.warn(
                        "Invalid #{CI::Ext::Settings::ENV_DYNAMIC_ATR_BUCKETS} value '#{values.join(",")}'; " \
                          "expected five comma-separated integers in [1, 20]"
                      )
                      nil
                    end
                  end
                end
              end

              option :test_management_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_TEST_MANAGEMENT_ENABLED
                o.default true
              end

              option :test_management_attempt_to_fix_retries_count do |o|
                o.type :int, nilable: true
                o.env CI::Ext::Settings::ENV_TEST_MANAGEMENT_ATTEMPT_TO_FIX_RETRIES
                o.default nil
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

              # Minitest treats any value, including "0", as disabling plugin auto-loading.
              option :minitest_no_plugins do |o|
                o.type :string, nilable: true
                o.env "MT_NO_PLUGINS"
              end

              option :test_optimization_cache_manifest_file do |o|
                o.type :string, nilable: true
                o.env CI::Ext::TestOptimizationCache::ENV_MANIFEST_FILE
              end

              option :test_optimization_cache_runfiles_dir do |o|
                o.type :string, nilable: true
                o.env CI::Ext::TestOptimizationCache::ENV_RUNFILES_DIR
              end

              option :test_optimization_cache_runfiles_manifest_file do |o|
                o.type :string, nilable: true
                o.env CI::Ext::TestOptimizationCache::ENV_RUNFILES_MANIFEST_FILE
              end

              option :test_optimization_cache_test_srcdir do |o|
                o.type :string, nilable: true
                o.env CI::Ext::TestOptimizationCache::ENV_TEST_SRCDIR
              end

              option :tia_static_dependencies_tracking_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_TIA_STATIC_DEPENDENCIES_TRACKING_ENABLED
                o.default true
              end

              option :tia_opened_files_coverage_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_TIA_OPENED_FILES_COVERAGE_ENABLED
                o.default true
              end

              option :code_coverage_report_upload_enabled do |o|
                o.type :bool
                o.env CI::Ext::Settings::ENV_CODE_COVERAGE_REPORT_UPLOAD_ENABLED
                o.default true
              end

              option :code_coverage_flags do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_CODE_COVERAGE_FLAGS
              end

              option :runtime_tags_overrides do |o|
                o.type :string, nilable: true
                o.env CI::Ext::Settings::ENV_RUNTIME_TAGS
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

      class RuntimeSettings
        include Base
        extend Settings

        option(:service) { |o| o.env "DD_SERVICE" }
        option(:env) { |o| o.env "DD_ENV" }
        option(:version) { |o| o.env "DD_VERSION" }
        option(:api_key) { |o| o.env "DD_API_KEY" }
        option(:site) { |o| o.env "DD_SITE" }
        option(:tags) do |o|
          o.default do
            environment.fetch("DD_TAGS", "").split(/[ ,]+/).each_with_object({}) do |entry, tags|
              key, value = entry.split(":", 2)
              tags[key] = value if key && value
            end
          end
        end
        option(:time_now_provider) { |o| o.default { -> { ::Time.now } } }
        option(:get_time_provider) { |o| o.default { ->(unit = :float_second) { ::Process.clock_gettime(::Process::CLOCK_MONOTONIC, unit) } } }

        settings :logger do
          option :instance
          option :level, default: ::Logger::WARN
        end

        settings :diagnostics do
          option(:debug) { |o|
            o.type :bool
            o.env "DD_TRACE_DEBUG"
            o.default false
          }
        end

        settings :agent do
          option :host
          option :port
          option :use_ssl
          option :timeout_seconds
          option :uds_path
          option(:url) { |o| o.env "DD_TRACE_AGENT_URL" }
          option(:host_from_environment) { |o| o.env "DD_AGENT_HOST" }
          option(:port_from_environment) { |o| o.env "DD_TRACE_AGENT_PORT" }
          option(:timeout_from_environment) { |o| o.env "DD_TRACE_AGENT_TIMEOUT_SECONDS" }
        end

        settings :telemetry do
          option(:enabled) { |o|
            o.type :bool
            o.env "DD_INSTRUMENTATION_TELEMETRY_ENABLED"
            o.default true
          }
          option(:agentless_enabled) { |o|
            o.type :bool
            o.default false
          }
          option(:shutdown_timeout_seconds) { |o| o.default 5.0 }
          option(:agentless_url_override) { |o| o.env "DD_TELEMETRY_AGENTLESS_URL" }
          option(:aggregation_interval) { |o|
            o.type :float
            o.env "DD_TELEMETRY_HEARTBEAT_INTERVAL"
            o.default 10.0
          }
          option(:buffer_size) { |o| o.default 10_000 }
        end

        def initialize(**options)
          super
          parsed_tags = tags
          [:service, :env, :version].each do |name|
            import_option_if_unset(name, parsed_tags[name.to_s]) if get_option(name).nil? && parsed_tags.key?(name.to_s)
          end
        end

        def service_without_fallback
          service
        end

        def import_legacy!(source)
          [:service, :env, :version, :site, :api_key, :tags, :time_now_provider, :get_time_provider].each do |name|
            next unless source.respond_to?(name)
            value = (name == :service && source.respond_to?(:service_without_fallback)) ? source.service_without_fallback : source.public_send(name)
            import_option_if_unset(name, value.is_a?(Hash) ? value.dup : value)
          end
          [:logger, :diagnostics, :agent, :telemetry].each do |name|
            next unless source.respond_to?(name)
            target = public_send(name)
            origin = source.public_send(name)
            target.class.options.each_key do |key|
              next unless origin.respond_to?(key)

              value = if name == :telemetry && key == :enabled &&
                  origin.respond_to?(:using_default?) && origin.using_default?(key)
                target.class.options.fetch(key).resolve(target)
              else
                origin.public_send(key)
              end
              target.import_option_if_unset(key, value)
            end
          end
          self
        end
      end
    end
  end
end
