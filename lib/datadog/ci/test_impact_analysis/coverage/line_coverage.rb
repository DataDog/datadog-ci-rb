# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # Per-test line coverage from the native line collector
        # (ext/datadog_ci_native/line_coverage.c).
        #
        # The collector records lines into contexts: one per test and one per suite
        # fixture (RSpec before(:context) hooks). The running fiber names its context in
        # fiber storage, which Ruby copies into every thread and fiber the context
        # creates. Lines that run in no open context are reported once per process, in
        # the unowned part of #shared.
        #
        # Errors are logged and never raised: the methods run inside customer tests.
        #
        # @internal
        class LineCoverage
          # A context and where it was set: the fiber and the context it replaced there.
          class Context
            attr_reader :serial, :fiber, :previous

            def initialize(serial, fiber, previous)
              @serial = serial
              @fiber = fiber
              @previous = previous
            end
          end

          EMPTY_COVERAGE = {}.freeze
          EMPTY_SHARED = {}.freeze

          # The native collector must be loaded first.
          def self.supported?
            return false unless defined?(LineCollector) && LineCollector.supported?

            # Without a way to keep repository code out of YJIT, lines in code that YJIT
            # compiled would stop being recorded.
            !defined?(RubyVM::YJIT) || LineCollector.yjit_supported?
          end

          # The paths the collector ignores besides the ones it always ignores, such as
          # vendor and hidden directories.
          def self.ignored_paths(bundle_location)
            return [] unless bundle_location && File.directory?(bundle_location)

            [File.join(File.realpath(bundle_location), "")]
          end

          # Returns nil when the collector cannot run in this process.
          #
          # The collector can start before Datadog is configured, and a later start with
          # the same root and ignored paths takes it over. It keeps the files it knows by
          # repository-relative path, so it never runs again for another root.
          def self.start(root:, ignored_paths:)
            unless supported?
              Datadog.logger.warn(
                "Per-test line coverage is not supported on this Ruby: falling back to file-level coverage"
              )
              return nil
            end

            running_with = @running_with
            if running_with && running_with != [root, ignored_paths]
              Datadog.logger.warn(
                "Per-test line coverage is running with repository root #{running_with[0]} and ignored paths " \
                "#{running_with[1]}, not #{root} and #{ignored_paths}: falling back to file-level coverage"
              )
              stop_collector
              return nil
            end

            first_root = @first_root
            if first_root && first_root != root
              Datadog.logger.warn(
                "Per-test line coverage first ran with repository root #{first_root}, not #{root}: " \
                "falling back to file-level coverage"
              )
              return nil
            end

            return nil unless LineCollector.start(root, ignored_paths)

            @first_root = root
            @running_with = [root, ignored_paths]
            new
          rescue => e
            Datadog.logger.warn("Failed to start per-test line coverage: #{e.class}: #{e.message}")
            nil
          end

          # Stops the collector if this process loaded and started it.
          def self.stop_collector
            @running_with = nil
            return unless defined?(LineCollector) && LineCollector.supported?

            LineCollector.stop
          rescue => e
            Datadog.logger.warn("Failed to stop per-test line coverage: #{e.class}: #{e.message}")
          end

          def initialize
            @mutex = Mutex.new
            @tests = {}
            @test_ids_by_serial = {}
            @fixtures = {}
            @open_fixture_id = nil
          end

          # Opens a context for the test in the current fiber.
          def start_test(test_id)
            @mutex.synchronize do
              close_open_fixture

              previous = Fiber[LineCollector::CONTEXT_KEY]
              previous = release_unfinished_test(previous)

              serial = LineCollector.open_context
              return if serial.nil?

              Fiber[LineCollector::CONTEXT_KEY] = serial
              @tests[test_id] = Context.new(serial, Fiber.current, previous)
              @test_ids_by_serial[serial] = test_id
            end
          rescue => e
            log_error("start a test", e)
          end

          # Closes the test's context and returns its lines, the lines of the fixtures it
          # depends on and the initialiser lines of the files with any of those, as line
          # bitmaps by repository-relative path.
          def finish_test(test_id, fixture_ids)
            @mutex.synchronize do
              context = remove_test(test_id)
              return EMPTY_COVERAGE if context.nil?

              fixture_serials = fixture_ids.filter_map { |fixture_id| @fixtures[fixture_id]&.serial }
              LineCollector.coverage(context.serial, fixture_serials)
            end
          rescue => e
            log_error("finish a test", e)
            EMPTY_COVERAGE
          end

          # Closes the test's context and drops its lines.
          def discard_test(test_id)
            @mutex.synchronize do
              context = remove_test(test_id)
              LineCollector.release(context.serial) if context
            end
          rescue => e
            log_error("discard a test", e)
          end

          # Opens a context for a suite fixture in the current fiber. It stays open until
          # the next test or fixture starts.
          def start_fixture(fixture_id)
            @mutex.synchronize do
              close_open_fixture
              release_fixture_context(@fixtures.delete(fixture_id))

              serial = LineCollector.open_context(true)
              return if serial.nil?

              previous = Fiber[LineCollector::CONTEXT_KEY]
              Fiber[LineCollector::CONTEXT_KEY] = serial
              @fixtures[fixture_id] = Context.new(serial, Fiber.current, previous)
              @open_fixture_id = fixture_id
            end
          rescue => e
            log_error("start a fixture", e)
          end

          # Called when the fixture's scope finishes: its lines move to the suite setup part
          # of #shared.
          def release_fixture(fixture_id)
            @mutex.synchronize do
              @open_fixture_id = nil if @open_fixture_id == fixture_id
              release_fixture_context(@fixtures.delete(fixture_id))
            end
          rescue => e
            log_error("release a fixture", e)
          end

          # Lines that are in no test's own lines, by part: "init", "suiteSetup" and
          # "unowned", each as line bitmaps by repository-relative path.
          def shared
            LineCollector.shared
          rescue => e
            log_error("collect shared lines", e)
            EMPTY_SHARED
          end

          def stop
            LineCoverage.stop_collector
          end

          private

          def close_open_fixture
            fixture_id = @open_fixture_id
            return if fixture_id.nil?

            @open_fixture_id = nil
            fixture = @fixtures[fixture_id]
            LineCollector.close_context(fixture.serial) if fixture
          end

          def release_fixture_context(fixture)
            return if fixture.nil?

            restore_fiber_context(fixture)
            LineCollector.release(fixture.serial)
          end

          def remove_test(test_id)
            context = @tests.delete(test_id)
            return if context.nil?

            @test_ids_by_serial.delete(context.serial)
            restore_fiber_context(context)
            context
          end

          # A test that started in this fiber and never finished would keep its context
          # open, so every line would keep trapping. Returns the context to restore when
          # the next test finishes.
          def release_unfinished_test(current)
            test_id = @test_ids_by_serial[current]
            return current if test_id.nil?

            context = @tests[test_id]
            # In a thread or fiber that the test created, the test is still running.
            return current unless context&.fiber&.equal?(Fiber.current)

            @tests.delete(test_id)
            @test_ids_by_serial.delete(current)
            Datadog.logger.debug { "Line coverage: released the context of a test that did not finish: #{test_id}" }
            LineCollector.release(context.serial)
            context.previous
          end

          # Only the fiber that set a context can change its storage.
          def restore_fiber_context(context)
            return unless Fiber.current.equal?(context.fiber)
            return unless Fiber[LineCollector::CONTEXT_KEY] == context.serial

            Fiber[LineCollector::CONTEXT_KEY] = context.previous
          end

          def log_error(action, error)
            Datadog.logger.warn("Line coverage failed to #{action}: #{error.class}: #{error.message}")
          end
        end
      end
    end
  end
end
