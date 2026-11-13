# frozen_string_literal: true

require_relative "file_dependencies"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        class OpenedFilesCollector
          def initialize(root:, ignored_path:)
            @resolver = FileDependencies.new(root: root, ignored_path: ignored_path)
            @collections = {}
            @mutex = Mutex.new
          end

          def start
            @mutex.synchronize do
              # Native collectors belong to the current fiber through Thread#[].
              # Replace the registry so readers can retain a snapshot without locking.
              @collections = @collections.merge(Fiber.current => @collections[Fiber.current] || {})
            end
          end

          def stop
            @mutex.synchronize do
              collections = @collections.dup
              collection = collections.delete(Fiber.current)
              @collections = collections
              collection || {}
            end
          end

          def record(file)
            collections = @collections
            record_into(collections, file) if collecting?(collections)
          end

          private

          def collecting?(collections)
            !collections.empty? && !Thread.current[:dd_logging_file_dependency_error]
          end

          def record_into(collections, file)
            paths = @resolver.paths_for(file)
            return if paths.empty?

            @mutex.synchronize do
              collections.each do |owner, collection|
                # Resolution releases the GVL. A stopped collection must stay unchanged.
                next unless @collections[owner].equal?(collection)

                paths.each { |path| collection[path] = true }
              end
            end
          rescue => error
            warn_failure(error)
          end

          def warn_failure(error)
            # Suppress file reads by the logger in this fiber, even if logging fails.
            Thread.current[:dd_logging_file_dependency_error] = true
            Datadog.logger.warn("Failed to collect file dependency: #{error}")
          rescue
            nil
          ensure
            Thread.current[:dd_logging_file_dependency_error] = false
          end
        end
      end
    end
  end
end
