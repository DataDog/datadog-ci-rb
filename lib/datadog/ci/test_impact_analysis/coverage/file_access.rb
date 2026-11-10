# frozen_string_literal: true

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # File dependencies supplement executed Ruby files. Hooks are installed only
        # when coverage starts; inactive hooks do not coerce arguments or inspect paths.
        class FileAccess
          @collectors = [].freeze
          @mutex = Mutex.new

          class << self
            def activate(collector)
              @mutex.synchronize do
                unless @installed
                  File.prepend(FileMethods)
                  IO.singleton_class.prepend(IOMethods)
                  @installed = true
                end
                @collectors = (@collectors | [collector]).freeze
              end
            end

            def deactivate(collector)
              @mutex.synchronize { @collectors = (@collectors - [collector]).freeze }
            end

            def active?
              !@collectors.empty?
            end

            def record(path)
              return unless active?
              return if Thread.current.thread_variable_get(:dd_file_access_recording)

              begin
                Thread.current.thread_variable_set(:dd_file_access_recording, true)
                absolute = File.absolute_path(path)
                # Retain both the name opened and its target: either can change.
                resolved = File.realpath(path) if File.exist?(path)
                @collectors.each do |collector|
                  collector.record(absolute, resolved)
                end
              rescue => e
                warn_failure(e)
              ensure
                Thread.current.thread_variable_set(:dd_file_access_recording, false)
              end
            end

            def prepare_path(path, pipes)
              path = File.path(path)
              record(path) unless pipes && path.start_with?("|")
              path
            end

            def record_file(file)
              record(file.path) if active? && file.path
            rescue => e
              warn_failure(e)
            end

            def warn_failure(error)
              Datadog.logger.warn("Failed to collect file dependencies: #{error}")
            rescue
              # Logging must not break the customer's file operation either.
              nil
            end
          end

          # File.open and Kernel.open both invoke File#initialize, whereas the
          # IO convenience methods open files directly in C and need separate hooks.
          module FileMethods
            def initialize(*args, **options)
              super
              FileAccess.record_file(self)
            end

            def reopen(*args, **options)
              result = super
              FileAccess.record_file(self)
              result
            end
          end

          module IOMethods
            # Coerce path-like objects exactly once, using the same conversion as
            # Ruby's IO methods. Keep customer conversion and IO exceptions intact.
            def read(path, *args, **options, &block)
              path = FileAccess.prepare_path(path, self == IO) if FileAccess.active?
              super
            end

            def binread(path, *args, **options, &block)
              path = FileAccess.prepare_path(path, self == IO) if FileAccess.active?
              super
            end

            def readlines(path, *args, **options, &block)
              path = FileAccess.prepare_path(path, self == IO) if FileAccess.active?
              super
            end

            def sysopen(path, *args, **options, &block)
              path = FileAccess.prepare_path(path, false) if FileAccess.active?
              super
            end

            def write(path, *args, **options, &block)
              path = FileAccess.prepare_path(path, self == IO) if FileAccess.active?
              super
            end

            def binwrite(path, *args, **options, &block)
              path = FileAccess.prepare_path(path, self == IO) if FileAccess.active?
              super
            end

            def foreach(path, *args, **options, &block)
              return enum_for(:foreach, path, *args, **options) unless block

              if FileAccess.active?
                path = File.path(path)
                FileAccess.record(path) unless self == IO && path.start_with?("|")
              end
              super
            end
          end

          def initialize(root:, ignored_path:, threading_mode:, inherit_on_fork: false, &filter)
            @root = File.join(File.absolute_path(root), "")
            @ignored_path = File.join(File.absolute_path(ignored_path), "") if ignored_path
            @single_threaded = threading_mode == :single
            @inherit_on_fork = inherit_on_fork
            @filter = filter
            @files = {}
            @mutex = Mutex.new
            @active = false
          end

          def start
            @mutex.synchronize do
              @files = {}
              @thread = Thread.current
              @pid = Process.pid
              @active = true
            end
            self.class.activate(self)
          rescue => e
            self.class.warn_failure(e)
          end

          def stop
            self.class.deactivate(self)
            @mutex.synchronize do
              @active = false
              files = @files
              @files = {}
              files
            end
          rescue => e
            self.class.warn_failure(e)
            {}
          end

          def record(absolute, resolved)
            @mutex.synchronize do
              return unless @active
              return unless @inherit_on_fork || @pid == Process.pid
              return if @single_threaded && @thread != Thread.current
              filter = @filter
              return if filter && !filter.call

              [absolute, resolved].each do |path|
                next unless path&.start_with?(@root)
                ignored_path = @ignored_path
                next if ignored_path && path.start_with?(ignored_path)

                @files[path] = true
              end
            end
          end
        end
      end
    end
  end
end
