# frozen_string_literal: true

require "rbconfig"

require_relative "context"
require_relative "telemetry"

require_relative "../codeowners/parser"
require_relative "../contrib/contrib"
require_relative "../ext/test"
require_relative "../ext/environment"
require_relative "../git/local_repository"

require_relative "../worker"

module Datadog
  module CI
    module TestVisibility
      # Common behavior for CI tests
      class Component
        attr_reader :test_suite_level_visibility_enabled

        def initialize(
          test_optimisation:,
          remote_settings_api:,
          git_tree_upload_worker: DummyWorker.new,
          test_suite_level_visibility_enabled: false,
          codeowners: Codeowners::Parser.new(Git::LocalRepository.root).parse
        )
          @test_suite_level_visibility_enabled = test_suite_level_visibility_enabled
          @context = Context.new(Ext::Environment.tags(ENV).freeze)
          @codeowners = codeowners
          @test_optimisation = test_optimisation
          @remote_settings_api = remote_settings_api
          @git_tree_upload_worker = git_tree_upload_worker
        end

        def shutdown!
          @git_tree_upload_worker.stop
        end

        def start_test_session(service: nil, tags: {})
          return skip_tracing unless test_suite_level_visibility_enabled

          test_session = @context.start_test_session(service: service, tags: tags)
          on_test_session_started(test_session)
          test_session
        end

        def start_test_module(test_module_name, service: nil, tags: {})
          return skip_tracing unless test_suite_level_visibility_enabled

          test_module = @context.start_test_module(test_module_name, service: service, tags: tags)
          on_test_module_started(test_module)
          test_module
        end

        def start_test_suite(test_suite_name, service: nil, tags: {})
          return skip_tracing unless test_suite_level_visibility_enabled

          test_suite = @context.start_test_suite(test_suite_name, service: service, tags: tags)
          on_test_suite_started(test_suite)
          test_suite
        end

        def trace_test(test_name, test_suite_name, service: nil, tags: {}, &block)
          if block
            @context.trace_test(test_name, test_suite_name, service: service, tags: tags) do |test|
              on_test_started(test)
              res = block.call(test)
              on_test_finished(test)
              res
            end
          else
            test = @context.trace_test(test_name, test_suite_name, service: service, tags: tags)
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
          @context.active_test_session
        end

        def active_test_module
          @context.active_test_module
        end

        def active_test_suite(test_suite_name)
          @context.active_test_suite(test_suite_name)
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

          @context.deactivate_test_suite(test_suite_name)
        end

        def itr_enabled?
          @test_optimisation.enabled?
        end

        private

        # DOMAIN EVENTS
        def on_test_session_started(test_session)
          Telemetry.event_created(test_session)

          # finds and instruments additional test libraries that we support (ex: selenium-webdriver)
          Contrib.auto_instrument_on_session_start!

          @git_tree_upload_worker.perform(test_session.git_repository_url)
          configure_library(test_session)
        end

        def on_test_module_started(test_module)
          Telemetry.event_created(test_module)
        end

        def on_test_suite_started(test_suite)
          Telemetry.event_created(test_suite)
        end

        def on_test_started(test)
          # sometimes test suite is not being assigned correctly
          # fix it by fetching the one single running test suite from the global context
          fix_test_suite!(test) if test.test_suite_id.nil?

          validate_test_suite_level_visibility_correctness(test)
          set_codeowners(test)

          Telemetry.event_created(test)

          @test_optimisation.mark_if_skippable(test)
          @test_optimisation.start_coverage(test)
        end

        def on_test_session_finished(test_session)
          @test_optimisation.write_test_session_tags(test_session)

          Telemetry.event_finished(test_session)
        end

        def on_test_module_finished(test_module)
          Telemetry.event_finished(test_module)
        end

        def on_test_suite_finished(test_suite)
          Telemetry.event_finished(test_suite)
        end

        def on_test_finished(test)
          @test_optimisation.stop_coverage(test)
          @test_optimisation.count_skipped_test(test)

          Telemetry.event_finished(test)
        end

        # TODO: move this to CI::Configuration::Remote
        def configure_library(test_session)
          # this will change when EFD is implemented
          return unless itr_enabled?

          remote_configuration = @remote_settings_api.fetch_library_settings(test_session)
          # sometimes we can skip code coverage for default branch if there are no changes in the repository
          # backend needs git metadata uploaded for this test session to check if we can skip code coverage
          if remote_configuration.require_git?
            Datadog.logger.debug { "Library configuration endpoint requires git upload to be finished, waiting..." }
            @git_tree_upload_worker.wait_until_done

            Datadog.logger.debug { "Requesting library configuration again..." }
            remote_configuration = @remote_settings_api.fetch_library_settings(test_session)

            if remote_configuration.require_git?
              Datadog.logger.debug { "git metadata upload did not complete in time when configuring library" }
            end
          end

          @test_optimisation.configure(
            remote_configuration.payload,
            test_session: test_session,
            git_tree_upload_worker: @git_tree_upload_worker
          )
        end

        # HELPERS
        def skip_tracing(block = nil)
          block&.call(nil)
        end

        def set_codeowners(test)
          source = test.source_file
          owners = @codeowners.list_owners(source) if source
          test.set_tag(Ext::Test::TAG_CODEOWNERS, owners) unless owners.nil?
        end

        def fix_test_suite!(test)
          test_suite = @context.single_active_test_suite
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
      end
    end
  end
end
