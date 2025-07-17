# frozen_string_literal: true

require_relative "../worker"
require_relative "../utils/stateful"
require_relative "library_settings"

module Datadog
  module CI
    module Remote
      # Remote configuration component.
      # Responsible for fetching library settings and configuring the library accordingly.
      class Component
        include Datadog::CI::Utils::Stateful

        FILE_STORAGE_KEY = "remote_component_state"

        def initialize(library_settings_client:, test_discovery_mode_enabled: false)
          @library_settings_client = library_settings_client
          @test_discovery_mode_enabled = test_discovery_mode_enabled
        end

        # called on test session start, uses test session info to send configuration request to the backend
        def configure(test_session)
          fetch_library_configuration(test_session)

          # configure different components in parallel because they might block on HTTP requests
          configuration_workers = [
            Worker.new { test_optimisation.configure(@library_configuration, test_session) },
            Worker.new { test_retries.configure(@library_configuration, test_session) },
            Worker.new { test_visibility.configure(@library_configuration, test_session) },
            Worker.new { test_management.configure(@library_configuration, test_session) },
            Worker.new { impacted_tests_detection.configure(@library_configuration, test_session) }
          ]

          # launch configuration workers
          configuration_workers.each(&:perform)

          # block until all workers are done (or 60 seconds has passed)
          configuration_workers.each(&:wait_until_done)
        end

        # Implementation of Stateful interface
        def serialize_state
          {
            library_configuration: @library_configuration
          }
        end

        def restore_state(state)
          @library_configuration = state[:library_configuration]
        end

        def storage_key
          FILE_STORAGE_KEY
        end

        private

        def fetch_library_configuration(test_session)
          # In test discovery mode, skip backend fetching and use default settings (everything is disabled)
          return @library_configuration = LibrarySettings.new(nil) if @test_discovery_mode_enabled

          # skip backend request if library configuration was loaded by a different process and stored on disk
          library_configuration_loaded = load_component_state
          return @library_configuration if library_configuration_loaded

          @library_configuration = @library_settings_client.fetch(test_session)

          # sometimes we can skip code coverage for default branch if there are no changes in the repository
          # backend needs git metadata uploaded for this test session to check if we can skip code coverage
          if @library_configuration.require_git?
            Datadog.logger.debug { "Library configuration endpoint requires git upload to be finished, waiting..." }
            git_tree_upload_worker.wait_until_done

            Datadog.logger.debug { "Requesting library configuration again..." }
            @library_configuration = @library_settings_client.fetch(test_session)

            if @library_configuration.require_git?
              Datadog.logger.debug { "git metadata upload did not complete in time when configuring library" }
            end
          end

          # Store component state for distributed test runs
          store_component_state if test_session.distributed

          @library_configuration
        end

        def test_management
          Datadog.send(:components).test_management
        end

        def test_visibility
          Datadog.send(:components).test_visibility
        end

        def test_optimisation
          Datadog.send(:components).test_optimisation
        end

        def test_retries
          Datadog.send(:components).test_retries
        end

        def impacted_tests_detection
          Datadog.send(:components).impacted_tests_detection
        end

        def git_tree_upload_worker
          Datadog.send(:components).git_tree_upload_worker
        end
      end
    end
  end
end
