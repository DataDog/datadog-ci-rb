# frozen_string_literal: true

require "pp"
require "coverage"

require "datadog/core/utils/forking"

require_relative "../ext/test"
require_relative "../ext/telemetry"

require_relative "../git/local_repository"

require_relative "../utils/parsing"
require_relative "../utils/telemetry"

require_relative "coverage/event"
require_relative "skippable"
require_relative "telemetry"

module Datadog
  module CI
    module TestOptimisation
      # Intelligent test runner implementation
      # Integrates with backend to provide test impact analysis data and
      # skip tests that are not impacted by the changes
      class Component
        include Core::Utils::Forking

        attr_reader :correlation_id, :skippable_tests, :skipped_tests_count

        def initialize(
          dd_env:,
          config_tags: {},
          api: nil,
          coverage_writer: nil,
          enabled: false,
          bundle_location: nil,
          use_single_threaded_coverage: false,
          use_allocation_tracing: true
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

          @test_skipping_enabled = false
          @code_coverage_enabled = false

          @coverage_writer = coverage_writer

          @correlation_id = nil
          @skippable_tests = Set.new

          @skipped_tests_count = 0
          @mutex = Mutex.new

          Datadog.logger.debug("TestOptimisation initialized with enabled: #{@enabled}")
        end

        def configure(remote_configuration, test_session)
          @covered_files = Set.new
          @trace = TracePoint.new(:line) do |tp|
            next unless tp.path.start_with?(Git::LocalRepository.root)
            @covered_files.add(tp.path)
          end

          @enabled = false
          return unless enabled?

          Datadog.logger.debug("Configuring TestOptimisation with remote configuration: #{remote_configuration}")

          @enabled = remote_configuration.itr_enabled?
          @enabled = false
          @test_skipping_enabled = @enabled && remote_configuration.tests_skipping_enabled?
          @code_coverage_enabled = @enabled && remote_configuration.code_coverage_enabled?

          @code_coverage_enabled = true

          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_ENABLED, @test_skipping_enabled)
          test_session.set_tag(Ext::Test::TAG_CODE_COVERAGE_ENABLED, @code_coverage_enabled)
          # we skip tests, not suites
          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_TYPE, Ext::Test::ITR_TEST_SKIPPING_MODE)

          load_datadog_cov! if @code_coverage_enabled

          Datadog.logger.debug("Configured TestOptimisation with enabled: #{@enabled}, skipping_tests: #{@test_skipping_enabled}, code_coverage: #{@code_coverage_enabled}")

          fetch_skippable_tests(test_session)
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

        def start_coverage(test)
          @trace.enable
          return if !enabled? || !code_coverage?

          Telemetry.code_coverage_started(test)
          coverage_collector&.start
        end

        def stop_coverage(test)
          @trace.disable

          result = @covered_files
          @covered_files = Set.new
          # p result
          # result

          return if !enabled? || !code_coverage?

          Telemetry.code_coverage_finished(test)

          coverage = coverage_collector&.stop

          # if test was skipped, we discard coverage data
          return if test.skipped?

          if coverage.nil? || coverage.empty?
            Telemetry.code_coverage_is_empty
            return
          end

          test_source_file = test.source_file

          # cucumber's gherkin files are not covered by the code coverage collector
          ensure_test_source_covered(test_source_file, coverage) unless test_source_file.nil?

          Telemetry.code_coverage_files(coverage.size)

          p coverage

          event = Coverage::Event.new(
            test_id: test.id.to_s,
            test_suite_id: test.test_suite_id.to_s,
            test_session_id: test.test_session_id.to_s,
            coverage: coverage
          )

          Datadog.logger.debug { "Writing coverage event \n #{event.pretty_inspect}" }

          write(event)

          event
        end

        def mark_if_skippable(test)
          return if !enabled? || !skipping_tests?

          datadog_test_id = Utils::TestRun.datadog_test_id(test.name, test.test_suite_name, test.parameters)
          if @skippable_tests.include?(datadog_test_id)
            if forked?
              Datadog.logger.warn { "Intelligent test runner is not supported for forking test runners yet" }
              return
            end

            test.set_tag(Ext::Test::TAG_ITR_SKIPPED_BY_ITR, "true")

            Datadog.logger.debug { "Marked test as skippable: #{datadog_test_id}" }
          else
            Datadog.logger.debug { "Test is not skippable: #{datadog_test_id}" }
          end
        end

        def count_skipped_test(test)
          return if !test.skipped? || !test.skipped_by_itr?

          if forked?
            Datadog.logger.warn { "Intelligent test runner is not supported for forking test runners yet" }
            return
          end

          @mutex.synchronize do
            Telemetry.itr_skipped

            @skipped_tests_count += 1
          end
        end

        def write_test_session_tags(test_session)
          return if !enabled?

          Datadog.logger.debug { "Finished optimised session with test skipping enabled: #{@test_skipping_enabled}" }
          Datadog.logger.debug { "#{@skipped_tests_count} tests were skipped" }

          test_session.set_tag(Ext::Test::TAG_ITR_TESTS_SKIPPED, @skipped_tests_count.positive?.to_s)
          test_session.set_tag(Ext::Test::TAG_ITR_TEST_SKIPPING_COUNT, @skipped_tests_count)
        end

        def shutdown!
          @coverage_writer&.stop
        end

        private

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
          require "datadog_cov.#{RUBY_VERSION}_#{RUBY_PLATFORM}"

          Datadog.logger.debug("Loaded Datadog code coverage collector, using coverage mode: #{code_coverage_mode}")
        rescue LoadError => e
          Datadog.logger.error("Failed to load coverage collector: #{e}. Code coverage will not be collected.")

          @code_coverage_enabled = false
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

          @correlation_id = skippable_response.correlation_id
          @skippable_tests = skippable_response.tests

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
      end
    end
  end
end
