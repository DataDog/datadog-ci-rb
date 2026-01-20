# frozen_string_literal: true

require "pp"

require "datadog/core/telemetry/logging"

require_relative "../ext/test"
require_relative "../ext/telemetry"
require_relative "../ext/dd_test"

require_relative "../git/local_repository"

require_relative "../source_code/static_dependencies"

require_relative "../utils/parsing"
require_relative "../utils/stateful"
require_relative "../utils/telemetry"

require_relative "coverage/event"
require_relative "skippable"
require_relative "telemetry"

module Datadog
  module CI
    module TestOptimisation
      # Test Impact Analysis implementation
      # Integrates with backend to provide test impact analysis data and
      # skip tests that are not impacted by the changes
      class Component
        include Datadog::CI::Utils::Stateful

        FILE_STORAGE_KEY = "test_optimisation_component_state"

        attr_reader :correlation_id, :skippable_tests, :skippable_tests_fetch_error,
          :enabled, :test_skipping_enabled, :code_coverage_enabled

        def initialize(
          dd_env:,
          config_tags: {},
          api: nil,
          coverage_writer: nil,
          enabled: false,
          bundle_location: nil,
          use_single_threaded_coverage: false,
          use_allocation_tracing: true,
          static_dependencies_tracking_enabled: false
        )
          @enabled = enabled
          @api = api
          @dd_env = dd_env
          @config_tags = config_tags || {}

          @bundle_location = if bundle_location && !File.absolute_path?(bundle_location)
            File.join(Git::LocalRepository.root, bundle_location)
          else
            bundle_location
          end
          @use_single_threaded_coverage = use_single_threaded_coverage
          @use_allocation_tracing = use_allocation_tracing
          @static_dependencies_tracking_enabled = static_dependencies_tracking_enabled

          @test_skipping_enabled = false
          @code_coverage_enabled = false

          @coverage_writer = coverage_writer

          @correlation_id = nil
          @skippable_tests = Set.new

          @mutex = Mutex.new

          # Context coverage: stores coverage collected during before(:context)/before(:all) hooks
          # keyed by context_id (e.g., RSpec scoped_id for example groups)
          # Only used when use_single_threaded_coverage is false (multi-threaded mode)
          @context_coverages = {}
          @context_coverages_mutex = Mutex.new

          # Currently active context ID for context coverage collection
          @current_context_id = nil
          @current_context_id_mutex = Mutex.new

          Datadog.logger.debug("TestOptimisation initialized with enabled: #{@enabled}")
        end

        def configure(remote_configuration, test_session)
          return unless enabled?

          Datadog.logger.debug("Configuring TestOptimisation with remote configuration: #{remote_configuration}")

          @enabled = remote_configuration.itr_enabled?
          @test_skipping_enabled = @enabled && remote_configuration.tests_skipping_enabled?
          @code_coverage_enabled = @enabled && remote_configuration.code_coverage_enabled?

          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_ENABLED, @test_skipping_enabled)
          test_session.set_tag(Ext::Test::TAG_CODE_COVERAGE_ENABLED, @code_coverage_enabled)
          # we skip tests, not suites
          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_TYPE, Ext::Test::ITR_TEST_SKIPPING_MODE)

          if @code_coverage_enabled
            load_datadog_cov!

            populate_static_dependencies_map!
          end

          # Load component state first, and if successful, skip fetching skippable tests
          # Also try to restore from DDTest cache if available
          if skipping_tests?
            return if load_component_state
            return if restore_state_from_datadog_test_runner

            fetch_skippable_tests(test_session)
            store_component_state if test_session.distributed
          end

          Datadog.logger.debug("Configured TestOptimisation with enabled: #{@enabled}, skipping_tests: #{@test_skipping_enabled}, code_coverage: #{@code_coverage_enabled}")
        end

        def enabled?
          @enabled
        end

        def skipping_tests?
          @test_skipping_enabled
        end

        def code_coverage?
          @code_coverage_enabled
        end

        # Starts coverage collection.
        # This is a low-level method that only starts the collector.
        #
        # @return [void]
        def start_coverage
          return if !enabled? || !code_coverage?

          coverage_collector&.start
        end

        # Stops coverage collection and returns raw coverage data.
        # This is a low-level method that only stops the collector.
        #
        # @return [Hash, nil] Raw coverage data or nil
        def stop_coverage
          return if !enabled? || !code_coverage?

          coverage_collector&.stop
        end

        # Called when a test context (e.g., RSpec example group with before(:context)) starts.
        # Starts collecting coverage that will be merged into all tests within this context.
        #
        # @param context_id [String] A stable identifier for the context (e.g., RSpec scoped_id)
        # @return [void]
        def on_test_context_started(context_id)
          return unless context_coverage_enabled?

          # Stop and store any existing context coverage before starting new one.
          # This ensures that outer context coverage is preserved when nested contexts start.
          stop_context_coverage_and_store

          Datadog.logger.debug { "Starting context coverage collection for context [#{context_id}]" }

          # Store the context_id we're collecting for
          @current_context_id_mutex.synchronize do
            @current_context_id = context_id
          end

          coverage_collector&.start
        end

        # Called when a test starts within a context. This method:
        # 1. Stops any in-progress context coverage collection and stores it
        # 2. Starts coverage collection for the test itself
        #
        # @param test [Datadog::CI::Test] The test that is starting
        # @return [void]
        def on_test_started(test)
          return if !enabled? || !code_coverage?

          # Stop any in-progress context coverage and store it
          stop_context_coverage_and_store

          Telemetry.code_coverage_started(test)

          context_ids = test.context_ids || []

          Datadog.logger.debug do
            "Starting test coverage for [#{test.name}] with context chain: #{context_ids.inspect}"
          end

          coverage_collector&.start
        end

        # Called when a test finishes. This method:
        # 1. Stops test coverage collection
        # 2. Merges context coverage from all relevant contexts
        # 3. Writes the combined coverage event
        # 4. Records ITR statistics if test was skipped by TIA
        #
        # @param test [Datadog::CI::Test] The test that finished
        # @param context [Datadog::CI::TestVisibility::Context] The test visibility context for ITR stats
        # @return [Datadog::CI::TestOptimisation::Coverage::Event, nil] The coverage event or nil
        def on_test_finished(test, context)
          return unless enabled?

          # Handle ITR statistics
          if test.skipped_by_test_impact_analysis?
            Telemetry.itr_skipped

            context.incr_tests_skipped_by_tia_count
          end

          # Handle code coverage
          return unless code_coverage?
          Telemetry.code_coverage_finished(test)

          coverage = coverage_collector&.stop

          # if test was skipped, we discard coverage data
          return if test.skipped?
          coverage ||= {}

          # Merge context coverage from all relevant contexts
          context_ids = test.context_ids || []
          merge_context_coverages_into_test(coverage, context_ids)

          if coverage.empty?
            Telemetry.code_coverage_is_empty
            return
          end

          # cucumber's gherkin files are not covered by the code coverage collector - we add them here explicitly
          test_source_file = test.source_file
          ensure_test_source_covered(test_source_file, coverage) unless test_source_file.nil?

          # if we have static dependencies tracking enabled then we can make the coverage
          # more precise by fetching which files we depend on based on constants usage
          enrich_coverage_with_static_dependencies(coverage)

          Telemetry.code_coverage_files(coverage.size)

          coverage_event = Coverage::Event.new(
            test_id: test.id.to_s,
            test_suite_id: test.test_suite_id.to_s,
            test_session_id: test.test_session_id.to_s,
            coverage: coverage
          )

          Datadog.logger.debug { "Writing coverage event \n #{coverage_event.pretty_inspect}" }

          write(coverage_event)

          coverage_event
        end

        # Clears stored context coverage for a specific context.
        # Should be called when a context finishes (e.g., after(:context) completes).
        #
        # @param context_id [String] The context ID to clear
        # @return [void]
        def clear_context_coverage(context_id)
          return unless context_coverage_enabled?

          @context_coverages_mutex.synchronize do
            @context_coverages.delete(context_id)

            Datadog.logger.debug { "Cleared context coverage for [#{context_id}]" }
          end
        end

        # Returns whether context coverage collection is enabled.
        # Context coverage is disabled in single-threaded mode.
        #
        # @return [Boolean]
        def context_coverage_enabled?
          enabled? && code_coverage? && !@use_single_threaded_coverage
        end

        def skippable?(datadog_test_id)
          return false if !enabled? || !skipping_tests?

          @mutex.synchronize { @skippable_tests.include?(datadog_test_id) }
        end

        def mark_if_skippable(test)
          return if !enabled? || !skipping_tests?

          if skippable?(test.datadog_test_id) && !test.attempt_to_fix?
            test.set_tag(Ext::Test::TAG_ITR_SKIPPED_BY_ITR, "true")

            Datadog.logger.debug { "Marked test as skippable: #{test.datadog_test_id}" }
          else
            Datadog.logger.debug { "Test is not skippable: #{test.datadog_test_id}" }
          end
        end

        def write_test_session_tags(test_session, skipped_tests_count)
          return if !enabled?

          Datadog.logger.debug { "Finished optimised session with test skipping enabled: #{@test_skipping_enabled}" }
          Datadog.logger.debug { "#{skipped_tests_count} tests were skipped" }

          test_session.set_tag(Ext::Test::TAG_ITR_TESTS_SKIPPED, skipped_tests_count.positive?.to_s)
          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT, skipped_tests_count)
        end

        def skippable_tests_count
          skippable_tests.count
        end

        def shutdown!
          @coverage_writer&.stop
        end

        # Implementation of Stateful interface
        def serialize_state
          {
            correlation_id: @correlation_id,
            skippable_tests: @skippable_tests
          }
        end

        def restore_state(state)
          @mutex.synchronize do
            @correlation_id = state[:correlation_id]
            @skippable_tests = state[:skippable_tests]
          end
        end

        def storage_key
          FILE_STORAGE_KEY
        end

        def restore_state_from_datadog_test_runner
          Datadog.logger.debug { "Restoring skippable tests from DDTest cache" }

          skippable_tests_data = load_json(Ext::DDTest::SKIPPABLE_TESTS_FILE_NAME)
          if skippable_tests_data.nil?
            Datadog.logger.debug { "Restoring skippable tests failed, will request again" }
            return false
          end

          Datadog.logger.debug { "Restored skippable tests from DDTest: #{skippable_tests_data}" }

          transformed_data = transform_test_runner_data(skippable_tests_data)

          Datadog.logger.debug { "Skippable tests after transformation: #{transformed_data}" }

          # Use the Skippable::Response class to parse the transformed data
          skippable_response = Skippable::Response.from_json(transformed_data)

          @mutex.synchronize do
            @correlation_id = skippable_response.correlation_id
            @skippable_tests = skippable_response.tests
          end

          Datadog.logger.debug { "Found [#{@skippable_tests.size}] skippable tests from context" }
          Datadog.logger.debug { "ITR correlation ID from context: #{@correlation_id}" }

          true
        end

        private

        # Transforms Test Runner skippable tests data format to the format expected by Skippable::Response
        #
        # Test Runner format:
        # {
        #   "correlationId": "abc123",
        #   "skippableTests": {
        #     "suite_name": {
        #       "test_name": [{"suite": "suite_name", "name": "test_name", "parameters": "{...}", "configurations": {}}]
        #     }
        #   }
        # }
        #
        # Expected format:
        # {
        #   "meta": {"correlation_id": "abc123"},
        #   "data": [{"type": "test", "attributes": {"suite": "suite_name", "name": "test_name", "parameters": "{...}"}}]
        # }
        def transform_test_runner_data(skippable_tests_data)
          skippable_tests = skippable_tests_data.fetch("skippableTests", {})

          # Pre-calculate array size for better memory allocation
          total_test_configs = skippable_tests.sum do |_, tests_hash|
            tests_hash.sum { |_, test_configs| test_configs.size }
          end

          data_array = Array.new(total_test_configs)
          index = 0

          skippable_tests.each_value do |tests_hash|
            tests_hash.each_value do |test_configs|
              test_configs.each do |test_config|
                data_array[index] = {
                  "type" => Ext::Test::ITR_TEST_SKIPPING_MODE,
                  "attributes" => {
                    "suite" => test_config["suite"],
                    "name" => test_config["name"],
                    "parameters" => test_config["parameters"]
                  }
                }
                index += 1
              end
            end
          end

          {
            "meta" => {
              "correlation_id" => skippable_tests_data["correlationId"]
            },
            "data" => data_array
          }
        end

        def write(event)
          # skip sending events if writer is not configured
          @coverage_writer&.write(event)
        end

        def coverage_collector
          Thread.current[:dd_coverage_collector] ||= Coverage::DDCov.new(
            root: Git::LocalRepository.root,
            ignored_path: @bundle_location,
            threading_mode: code_coverage_mode,
            use_allocation_tracing: @use_allocation_tracing
          )
        end

        def load_datadog_cov!
          require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

          Datadog.logger.debug("Loaded Datadog code coverage collector, using coverage mode: #{code_coverage_mode}")
        rescue LoadError => e
          Datadog.logger.error("Failed to load coverage collector: #{e}. Code coverage will not be collected.")
          Core::Telemetry::Logger.report(e, description: "Failed to load coverage collector")

          @code_coverage_enabled = false
        end

        def populate_static_dependencies_map!
          return unless @code_coverage_enabled
          return unless @static_dependencies_tracking_enabled

          Datadog::CI::SourceCode::StaticDependencies.populate!(Git::LocalRepository.root, @bundle_location)
        end

        def enrich_coverage_with_static_dependencies(coverage)
          return unless @static_dependencies_tracking_enabled

          static_dependencies_map = {}
          coverage.keys.each do |file|
            static_dependencies_map.merge!(
              Datadog::CI::SourceCode::StaticDependencies.fetch_static_dependencies(file)
            )
          end
          coverage.merge!(static_dependencies_map)
        end

        def ensure_test_source_covered(test_source_file, coverage)
          absolute_test_source_file_path = File.join(Git::LocalRepository.root, test_source_file)
          return if coverage.key?(absolute_test_source_file_path)

          coverage[absolute_test_source_file_path] = true
        end

        def fetch_skippable_tests(test_session)
          return unless skipping_tests?

          # we can only request skippable tests if git metadata is already uploaded
          git_tree_upload_worker.wait_until_done

          skippable_response =
            Skippable.new(api: @api, dd_env: @dd_env, config_tags: @config_tags)
              .fetch_skippable_tests(test_session)
          @skippable_tests_fetch_error = skippable_response.error_message unless skippable_response.ok?

          @mutex.synchronize do
            @correlation_id = skippable_response.correlation_id
            @skippable_tests = skippable_response.tests
          end

          Datadog.logger.debug { "Fetched skippable tests: \n #{@skippable_tests}" }
          Datadog.logger.debug { "Found #{@skippable_tests.count} skippable tests." }
          Datadog.logger.debug { "ITR correlation ID: #{@correlation_id}" }

          Utils::Telemetry.inc(Ext::Telemetry::METRIC_ITR_SKIPPABLE_TESTS_RESPONSE_TESTS, @skippable_tests.count)
        end

        def code_coverage_mode
          @use_single_threaded_coverage ? :single : :multi
        end

        def git_tree_upload_worker
          Datadog.send(:components).git_tree_upload_worker
        end

        # Stops any in-progress context coverage collection and stores it.
        # Called when a test starts to capture coverage from before(:context) hooks.
        def stop_context_coverage_and_store
          return unless context_coverage_enabled?

          context_id = @current_context_id_mutex.synchronize do
            id = @current_context_id
            @current_context_id = nil
            id
          end
          return if context_id.nil?

          coverage = coverage_collector&.stop
          return if coverage.nil? || coverage.empty?

          @context_coverages_mutex.synchronize do
            @context_coverages[context_id] = coverage
          end

          Datadog.logger.debug do
            "Stored context coverage for [#{context_id}] with #{coverage.size} files"
          end
        end

        # Merges context coverage from all relevant contexts into the test's coverage.
        #
        # @param coverage [Hash] The test's coverage hash to merge into
        # @param context_ids [Array<String>] List of context IDs to merge coverage from
        def merge_context_coverages_into_test(coverage, context_ids)
          return if @use_single_threaded_coverage
          return if context_ids.empty?

          merged_files_count = 0

          @context_coverages_mutex.synchronize do
            context_ids.each do |context_id|
              context_coverage = @context_coverages[context_id]
              next unless context_coverage

              context_coverage.each do |file, _|
                unless coverage.key?(file)
                  coverage[file] = true
                  merged_files_count += 1
                end
              end
            end
          end

          if merged_files_count > 0
            Datadog.logger.debug do
              "Merged #{merged_files_count} files from context coverage " \
              "(contexts: #{context_ids.inspect}) into test coverage"
            end
          end
        end
      end
    end
  end
end
