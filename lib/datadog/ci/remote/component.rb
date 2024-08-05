# frozen_string_literal: true

module Datadog
  module CI
    module Remote
      # Remote configuration component.
      # Responsible for fetching library settings and configuring the library accordingly.
      class Component
        def initialize(library_settings_client:)
          @library_settings_client = library_settings_client
        end

        # called on test session start, uses test session info to send configuration request to the backend
        def configure(test_session)
          library_configuration = @library_settings_client.fetch(test_session)
          # sometimes we can skip code coverage for default branch if there are no changes in the repository
          # backend needs git metadata uploaded for this test session to check if we can skip code coverage
          if library_configuration.require_git?
            Datadog.logger.debug { "Library configuration endpoint requires git upload to be finished, waiting..." }
            git_tree_upload_worker.wait_until_done

            Datadog.logger.debug { "Requesting library configuration again..." }
            library_configuration = @library_settings_client.fetch(test_session)

            if library_configuration.require_git?
              Datadog.logger.debug { "git metadata upload did not complete in time when configuring library" }
            end
          end

          test_optimisation.configure(library_configuration, test_session)
          test_retries.configure(library_configuration)
        end

        private

        def test_optimisation
          Datadog.send(:components).test_optimisation
        end

        def test_retries
          Datadog.send(:components).test_retries
        end

        def git_tree_upload_worker
          Datadog.send(:components).git_tree_upload_worker
        end
      end
    end
  end
end
