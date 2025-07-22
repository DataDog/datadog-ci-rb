# frozen_string_literal: true

require "drb"
require "rbconfig"

require "datadog/core/utils/forking"

require_relative "context"
require_relative "telemetry"
require_relative "total_coverage"

require_relative "../codeowners/parser"
require_relative "../contrib/instrumentation"
require_relative "../ext/test"
require_relative "../git/local_repository"
require_relative "../utils/file_storage"
require_relative "../utils/stateful"

require_relative "../worker"

module Datadog
  module CI
    module TestVisibility
      # Core functionality of the library: tracing tests' execution
      class Component
        include Core::Utils::Forking
        include Datadog::CI::Utils::Stateful

        FILE_STORAGE_KEY = "test_visibility_component_state"

        attr_reader :test_suite_level_visibility_enabled, :logical_test_session_name,
          :known_tests, :known_tests_enabled, :context_service_uri, :local_test_suites_mode

        def initialize(
          known_tests_client:,
          test_suite_level_visibility_enabled: false,
          codeowners: Codeowners::Parser.new(Git::LocalRepository.root).parse,
          logical_test_session_name: nil,
          context_service_uri: nil
        )
          @test_suite_level_visibility_enabled = test_suite_level_visibility_enabled

          @context = Context.new(test_visibility_component: self)

          @codeowners = codeowners
          @logical_test_session_name = logical_test_session_name

          # "Known tests" feature fetches a list of all tests known to Datadog for this repository
          # and uses this list to determine if a test is new or not. New tests are marked with "test.is_new" tag.
          @known_tests_enabled = false
          @known_tests_client = known_tests_client
          @known_tests = Set.new

          # this is used for parallel test runners such as parallel_tests
          if context_service_uri
            @context_service_uri = context_service_uri
            @is_client_process = true
          end

          # This is used for parallel test runners such as parallel_tests.
          # If true, then test suites are created in the worker process, not the parent.
          #
          # The only test runner that requires creating test suites in the remote process is rails test runner because
          # it splits workload by test, not by test suite.
          #
          # Another test runner that splits workload by test is knapsack_pro, but we lack distributed test sessions/test suties
          # support for that one (as of 2025-03).
          @local_test_suites_mode = true
        end

        def configure(library_configuration, test_session)
          return unless test_suite_level_visibility_enabled
          return unless library_configuration.known_tests_enabled?

          @known_tests_enabled = true
          return if load_component_state

          fetch_known_tests(test_session)
          store_component_state if test_session.distributed
        end

        def start_test_session(service: nil, tags: {}, estimated_total_tests_count: 0, distributed: false, local_test_suites_mode: true)
          return skip_tracing unless test_suite_level_visibility_enabled

          @local_test_suites_mode = local_test_suites_mode

          start_drb_service

          test_session = maybe_remote_context.start_test_session(service: service, tags: tags)
          test_session.estimated_total_tests_count = estimated_total_tests_count
          test_session.distributed = distributed

          on_test_session_started(test_session)

          test_session
        end

        def start_test_module(test_module_name, service: nil, tags: {})
          return skip_tracing unless test_suite_level_visibility_enabled

          test_module = maybe_remote_context.start_test_module(test_module_name, service: service, tags: tags)
          on_test_module_started(test_module)

          test_module
        end

        def start_test_suite(test_suite_name, service: nil, tags: {})
          return skip_tracing unless test_suite_level_visibility_enabled

          context = @local_test_suites_mode ? @context : maybe_remote_context

          test_suite = context.start_test_suite(test_suite_name, service: service, tags: tags)
          on_test_suite_started(test_suite)
          test_suite
        end

        def trace_test(test_name, test_suite_name, service: nil, tags: {}, &block)
          test_suite = active_test_suite(test_suite_name)
          tags[Ext::Test::TAG_SUITE] ||= test_suite_name

          if block
            @context.trace_test(test_name, test_suite, service: service, tags: tags) do |test|
              subscribe_to_after_stop_event(test.tracer_span)

              on_test_started(test)
              res = block.call(test)
              on_test_finished(test)
              res
            end
          else
            test = @context.trace_test(test_name, test_suite, service: service, tags: tags)
            subscribe_to_after_stop_event(test.tracer_span)
            on_test_started(test)
            test
          end
        end

        def trace(span_name, type: "span", tags: {}, &block)
          if block
            @context.trace(span_name, type: type, tags: tags) do |span|
              block.call(span)
            end
          else
            @context.trace(span_name, type: type, tags: tags)
          end
        end

        def active_span
          @context.active_span
        end

        def active_test
          @context.active_test
        end

        def active_test_session
          maybe_remote_context.active_test_session
        end

        def active_test_module
          maybe_remote_context.active_test_module
        end

        def active_test_suite(test_suite_name)
          # when fetching test_suite to use as test's context, try local context instance first
          local_test_suite = @context.active_test_suite(test_suite_name)
          return local_test_suite if local_test_suite

          maybe_remote_context.active_test_suite(test_suite_name)
        end

        def deactivate_test
          test = active_test
          on_test_finished(test) if test

          @context.deactivate_test
        end

        def deactivate_test_session
          test_session = active_test_session
          on_test_session_finished(test_session) if test_session

          @context.deactivate_test_session
        end

        def deactivate_test_module
          test_module = active_test_module
          on_test_module_finished(test_module) if test_module

          @context.deactivate_test_module
        end

        def deactivate_test_suite(test_suite_name)
          test_suite = active_test_suite(test_suite_name)
          on_test_suite_finished(test_suite) if test_suite

          # deactivation always happens on the same process where test suite is located
          @context.deactivate_test_suite(test_suite_name)
        end

        def total_tests_count
          maybe_remote_context.total_tests_count
        end

        def tests_skipped_by_tia_count
          maybe_remote_context.tests_skipped_by_tia_count
        end

        def itr_enabled?
          test_optimisation.enabled?
        end

        def shutdown!
          # noop, there is no thread owned by test visibility component
        end

        def client_process?
          # We cannot assume here that every forked process is a client process
          # there are examples of custom test runners that run tests in forks but don't have a test session
          # started in the parent process.
          # So we need to check if the process is forked and if the context service URI is not empty.
          (forked? && !@context_service_uri.nil? && !@context_service_uri.empty?) || @is_client_process
        end

        private

        # DOMAIN EVENTS
        def on_test_session_started(test_session)
          # signal git tree upload worker to start uploading git metadata
          git_tree_upload_worker.perform(test_session.git_repository_url)

          # finds and instruments additional test libraries that we support (ex: selenium-webdriver)
          Contrib::Instrumentation.instrument_on_session_start

          # sets logical test session name if none provided by the user
          override_logical_test_session_name!(test_session) if logical_test_session_name.nil?

          # Signal Remote::Component to configure the library.
          # Note that it will call this component back (unfortunate circular dependency).
          remote.configure(test_session)
        end

        # intentionally empty
        def on_test_module_started(test_module)
        end

        def on_test_suite_started(test_suite)
          set_codeowners(test_suite)
        end

        def on_test_started(test)
          maybe_remote_context.incr_total_tests_count

          # Sometimes test suite is not being assigned correctly.
          # Fix it by fetching the one single running test suite from the process context.
          #
          # This is a hack to fix some edge cases that come from some minitest plugins,
          # especially thoughtbot/shoulda-context.
          fix_test_suite!(test) if test.test_suite_id.nil?
          validate_test_suite_level_visibility_correctness(test)

          set_codeowners(test)

          Telemetry.event_created(test)

          mark_test_as_new(test) if new_test?(test)

          impacted_tests_detection.tag_modified_test(test)

          test_management.tag_test_from_properties(test)

          test_optimisation.mark_if_skippable(test)
          test_optimisation.start_coverage(test)

          test_retries.record_test_started(test)
        end

        def on_test_session_finished(test_session)
          test_optimisation.write_test_session_tags(test_session, maybe_remote_context.tests_skipped_by_tia_count)

          TotalCoverage.extract_lines_pct(test_session)

          Telemetry.event_finished(test_session)

          Utils::FileStorage.cleanup
        end

        def on_test_module_finished(test_module)
          @context.stop_all_test_suites

          Telemetry.event_finished(test_module)
        end

        def on_test_suite_finished(test_suite)
          Telemetry.event_finished(test_suite)
        end

        def on_test_finished(test)
          test_optimisation.stop_coverage(test)
          test_optimisation.on_test_finished(test, maybe_remote_context)

          test_retries.record_test_finished(test)
          Telemetry.event_finished(test)
        end

        def on_after_test_span_finished(tracer_span)
          test_retries.record_test_span_duration(tracer_span)
        end

        # HELPERS
        def skip_tracing(block = nil)
          block&.call(nil)
        end

        def subscribe_to_after_stop_event(tracer_span)
          events = tracer_span.send(:events)

          events.after_stop.subscribe do |span|
            on_after_test_span_finished(span)
          end
        end

        def set_codeowners(span)
          source = span.source_file
          owners = @codeowners.list_owners(source) if source
          span.set_tag(Ext::Test::TAG_CODEOWNERS, owners) unless owners.nil?
        end

        def fix_test_suite!(test)
          return unless test_suite_level_visibility_enabled

          test_suite = maybe_remote_context.single_active_test_suite
          unless test_suite
            Datadog.logger.debug do
              "Trying to fix test suite for test [#{test.name}] but no single test suite is running."
            end
            return
          end

          Datadog.logger.debug do
            "For test [#{test.name}]: expected test suite [#{test.test_suite_name}] to be running, " \
            "but it was not found. Fixing it by assigning test suite [#{test_suite.name}] to the test."
          end

          test.set_tag(Ext::Test::TAG_TEST_SUITE_ID, test_suite.id.to_s)
          test.set_tag(Ext::Test::TAG_SUITE, test_suite.name)
        end

        def validate_test_suite_level_visibility_correctness(test)
          return unless test_suite_level_visibility_enabled

          if test.test_suite_id.nil?
            Datadog.logger.debug do
              "Test [#{test.name}] does not have a test suite associated with it. " \
              "Expected test suite [#{test.test_suite_name}] to be running."
            end
          end

          if test.test_module_id.nil?
            Datadog.logger.debug do
              "Test [#{test.name}] does not have a test module associated with it. " \
              "Make sure that there is a test module running within a session."
            end
          end

          if test.test_session_id.nil?
            Datadog.logger.debug do
              "Test [#{test.name}] does not have a test session associated with it. " \
              "Make sure that there is a test session running."
            end
          end
        end

        def override_logical_test_session_name!(test_session)
          @logical_test_session_name = test_session.test_command
          ci_job_name = test_session.ci_job_name
          if ci_job_name
            @logical_test_session_name = "#{ci_job_name}-#{@logical_test_session_name}"
          end
        end

        def new_test?(test_span)
          return false unless @known_tests_enabled

          test_id = Utils::TestRun.datadog_test_id(test_span.name, test_span.test_suite_name)
          result = !@known_tests.include?(test_id)

          if result
            Datadog.logger.debug do
              "#{test_id} is not found in the known tests set, it is a new test"
            end
          end

          result
        end

        def fetch_known_tests(test_session)
          @known_tests = @known_tests_client.fetch(test_session)

          if @known_tests.empty?
            @known_tests_enabled = false

            # this adds unfortunate knowledge on EFD from Testvisibility, rethink this
            test_session&.set_tag(Ext::Test::TAG_EARLY_FLAKE_ABORT_REASON, Ext::Test::EARLY_FLAKE_FAULTY)

            Datadog.logger.warn("Empty set of tests known to Datadog")
          end

          # report how many known tests were found
          Datadog.logger.debug do
            "Found [#{@known_tests.size}] known tests"
          end
          Utils::Telemetry.distribution(
            Ext::Telemetry::METRIC_KNOWN_TESTS_RESPONSE_TESTS,
            @known_tests.size.to_f
          )

          @known_tests
        end

        def mark_test_as_new(test_span)
          test_span.set_tag(Ext::Test::TAG_IS_NEW, "true")
        end

        def test_optimisation
          Datadog.send(:components).test_optimisation
        end

        def test_retries
          Datadog.send(:components).test_retries
        end

        def git_tree_upload_worker
          Datadog.send(:components).git_tree_upload_worker
        end

        def remote
          Datadog.send(:components).ci_remote
        end

        def test_management
          Datadog.send(:components).test_management
        end

        def impacted_tests_detection
          Datadog.send(:components).impacted_tests_detection
        end

        # DISTRIBUTED RUBY CONTEXT
        def start_drb_service
          return if @context_service_uri
          return if client_process?
          # it doesn't make sense to start DRb in a fork - we are already running in a forked process
          # and there is no parent process to communicate with
          return if forked?

          @context_service = DRb.start_service("drbunix:", @context)
          @context_service_uri = @context_service.uri
        end

        # depending on whether we are in a forked process or not, returns either the global context or its DRbObject
        def maybe_remote_context
          return @context unless client_process?
          return @context_client if defined?(@context_client)

          # at least once per fork we must stop the running DRb server that was copied from the parent process
          # otherwise, client will be confused thinking it's server which leads to terrible bugs
          @context_service&.stop_service

          @context_client = DRbObject.new_with_uri(@context_service_uri)
        end

        # Implementation of Stateful interface
        def serialize_state
          {
            known_tests: @known_tests
          }
        end

        def restore_state(state)
          @known_tests = state[:known_tests]
        end

        def storage_key
          FILE_STORAGE_KEY
        end
      end
    end
  end
end
