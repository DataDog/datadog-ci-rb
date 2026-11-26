# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Datadog
  module CI
    module TestImpactAnalysis
      module Coverage
        # The lines of the processes that a test starts, which count for that test.
        #
        # The spawn methods are hooked (see ChildProcessHooks). A spawn adds two entries to
        # the child's environment: ENV_CONTEXT, the prefix of the spawning context's records
        # in a transport directory, and RUBYOPT with "-r" and the child bootstrap first.
        # A Ruby child loads the bootstrap, which opens one context for the whole process
        # and writes its lines to "<prefix>.<pid>.lines" at exit; its own children inherit
        # the environment and do the same. A forked child keeps the context of the thread
        # that forked and writes the same record at exit, with the lines it ran outside
        # contexts since the fork.
        #
        # Bundler keeps the RUBYOPT of the process that first loaded it in
        # ENV_BUNDLER_ORIGINAL_RUBYOPT, and a process that runs a command with Bundler's
        # original or unbundled environment restores RUBYOPT from it, as puma does when it
        # restarts or prunes the bundle. When the child's environment has that entry, the
        # bootstrap goes first there too, so that such commands stay covered.
        #
        # Collection starts when a test session collects line coverage
        # (LineCoverage#collect_child_processes). A child started without a context gets
        # the unowned prefix. A spawn that clears the environment (unsetenv_others) or
        # RUBYOPT starts an uncovered child.
        #
        # @internal
        class ChildProcesses
          ENV_CONTEXT = "DD_TEST_OPTIMIZATION_TIA_LINE_COVERAGE_CHILD"
          ENV_RUBYOPT = "RUBYOPT"
          ENV_BUNDLER_ORIGINAL_RUBYOPT = "BUNDLER_ORIG_RUBYOPT"
          # What Bundler keeps in ENV_BUNDLER_ORIGINAL_RUBYOPT when RUBYOPT was not set.
          BUNDLER_UNSET = "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"
          BOOTSTRAP = File.expand_path("child_bootstrap.rb", File.dirname(__FILE__))
          CONFIG_FILE = "config"
          RECORD_SUFFIX = ".lines"
          UNOWNED = "unowned"

          class << self
            # The running instance, which the spawn hooks use; nil when child processes are
            # not collected.
            attr_reader :current

            # Returns nil when children of this process cannot be collected: RUBYOPT
            # cannot name a bootstrap path with spaces.
            def start(root:, ignored_paths:)
              return @current if @current

              extension_path = loaded_extension_path
              return nil if extension_path.nil? || BOOTSTRAP.match?(/\s/)

              @current = new(root: root, ignored_paths: ignored_paths, extension_path: extension_path)
              ChildProcessHooks.install
              @current
            rescue => e
              Datadog.logger.warn("Per-test line coverage will not collect child processes: #{e.class}: #{e.message}")
              nil
            end

            def stop
              child_processes = @current
              @current = nil
              child_processes&.remove_directory
            end

            # The arguments of a spawn call, with the child's environment entries added.
            def spawn_arguments(arguments)
              child_processes = @current
              return arguments if child_processes.nil?

              child_processes.spawn_arguments(arguments)
            rescue => e
              Datadog.logger.debug { "Line coverage did not cover a child process: #{e.class}: #{e.message}" }
              arguments
            end

            # The environment for a command string run by Kernel#`, or nil to run it as it is.
            def command_environment
              child_processes = @current
              return nil if child_processes.nil?

              child_processes.environment(nil)
            rescue => e
              Datadog.logger.debug { "Line coverage did not cover a child process: #{e.class}: #{e.message}" }
              nil
            end

            # Creates the transport directory before the fork, so that the child writes
            # where this process reads.
            def before_fork
              @current&.record_spawn(context)
            rescue => e
              Datadog.logger.debug { "Line coverage did not cover a forked process: #{e.class}: #{e.message}" }
            end

            def after_fork_in_child
              @current&.write_record_at_exit
            rescue => e
              Datadog.logger.debug { "Line coverage did not cover a forked process: #{e.class}: #{e.message}" }
            end

            def context
              Fiber[LineCollector::CONTEXT_KEY]
            end

            # The Ruby a child must run to load the same native extension.
            def identity
              [RUBY_ENGINE, RUBY_VERSION, RUBY_PATCHLEVEL, RUBY_REVISION, RUBY_PLATFORM].join(" ")
            end

            # A record: the packed bitmaps of the child's context (see LineFiles), as a
            # 32-bit big-endian length and the bytes, then the child's other lines as
            # length-prefixed path and bitmap pairs. Returns bitmaps by path.
            def decode_record(data)
              bitmaps = LineFiles.unpack(take_field(data, 0))
              offset = 4 + field_length(data, 0)
              while offset < data.bytesize
                file = take_field(data, offset)
                offset += 4 + file.bytesize
                bitmap = take_field(data, offset)
                offset += 4 + bitmap.bytesize
                file = file.force_encoding(Encoding::UTF_8)
                bitmaps[file] = LineFiles.union(bitmaps[file], bitmap)
              end
              bitmaps
            end

            def take_field(data, offset)
              length = field_length(data, offset)
              raise ArgumentError, "truncated record" if offset + 4 + length > data.bytesize

              data.byteslice(offset + 4, length) || ""
            end

            def field_length(data, offset)
              length = data.byteslice(offset, 4)&.unpack1("N")
              raise ArgumentError, "truncated record" unless length.is_a?(Integer)

              length
            end

            def loaded_extension_path
              name = "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}."
              $LOADED_FEATURES.find { |feature| File.basename(feature).start_with?(name) }
            end
          end

          def initialize(root:, ignored_paths:, extension_path:)
            @config = [self.class.identity, extension_path, root, *ignored_paths].join("\n")
            @owner_pid = Process.pid
            @require_option = "-r#{BOOTSTRAP}"
            @mutex = Mutex.new
            @directory = nil
            @spawned_prefixes = {}
          end

          # The transport directory, created at the first spawn and removed when this
          # process exits.
          def directory
            @mutex.synchronize do
              @directory ||= begin
                directory = Dir.mktmpdir("datadog-ci-line-coverage-")
                File.write(File.join(directory, CONFIG_FILE), @config)
                owner_pid = @owner_pid
                at_exit { FileUtils.rm_rf(directory) if Process.pid == owner_pid }
                directory
              end
            end
          end

          def spawn_arguments(arguments)
            options = arguments.last if arguments.size > 1
            return arguments if options.is_a?(Hash) && (options[:unsetenv_others] || options["unsetenv_others"])

            first = arguments.first
            caller_environment = first.is_a?(Hash) ? first : nil
            additions = environment(caller_environment)
            return arguments if additions.nil?

            if caller_environment
              [caller_environment.merge(additions), *arguments.drop(1)]
            else
              [additions, *arguments]
            end
          end

          # The entries to add to the environment of a child of the current context, or nil
          # when the child must not be covered.
          def environment(caller_environment)
            return nil if caller_environment&.key?(ENV_CONTEXT)

            rubyopt = child_value(caller_environment, ENV_RUBYOPT)
            return nil if caller_environment&.key?(ENV_RUBYOPT) && rubyopt.nil?

            prefix = record_spawn(self.class.context)
            entries = {
              ENV_CONTEXT => prefix,
              ENV_RUBYOPT => with_bootstrap(rubyopt)
            }
            bundler_rubyopt = bundler_original_rubyopt(child_value(caller_environment, ENV_BUNDLER_ORIGINAL_RUBYOPT))
            entries[ENV_BUNDLER_ORIGINAL_RUBYOPT] = bundler_rubyopt if bundler_rubyopt
            entries
          end

          def record_spawn(serial)
            prefix = prefix_for(serial)
            @mutex.synchronize { @spawned_prefixes[prefix] = true }
            File.join(directory, prefix)
          end

          # In a forked child: keeps the forking thread's context, or opens one for the
          # whole process, and has the collector write its lines at exit, after the exit
          # handlers. The record holds the lines the child runs outside contexts from now on.
          def write_record_at_exit
            serial = self.class.context
            # Set before the fork, so no lock that a thread of the parent held is needed.
            prefix = File.join(@directory || directory, prefix_for(serial))
            if serial.nil?
              serial = LineCollector.open_context
              return if serial.nil?

              Fiber[LineCollector::CONTEXT_KEY] = serial
            end
            LineCollector.write_record_at_exit(prefix, serial, true)
          end

          # Records of the finished children of a context, as bitmaps by path. A taken
          # record is removed; a kept one is read again later.
          def records(serial, keep: false)
            prefix = prefix_for(serial)
            return [] unless @mutex.synchronize { @spawned_prefixes.key?(prefix) }

            read_records(record_names.select { |name| name.start_with?("#{prefix}.") }, keep)
          end

          # Records that no test took, by context serial; nil for the unowned prefix.
          def remaining_records
            remaining = Hash.new { |records, serial| records[serial] = [] }
            record_names.each do |name|
              prefix = name.split(".", 2).first
              serial = (prefix == UNOWNED) ? nil : Integer(prefix.delete_prefix("c"), 10)
              remaining[serial].concat(read_records([name], false))
            end
            remaining
          end

          def remove_directory
            directory = @mutex.synchronize { @directory }
            FileUtils.rm_rf(directory) if directory && Process.pid == @owner_pid
          end

          private

          # The value the child gets: the caller's entry, or the inherited one.
          def child_value(caller_environment, name)
            if caller_environment&.key?(name)
              caller_environment[name]
            else
              ENV[name]
            end
          end

          # The bootstrap goes first, so that the child's collector already runs when the
          # libraries that RUBYOPT names load. bundler/setup is one: it runs the gemspec,
          # which may load repository files.
          def with_bootstrap(rubyopt)
            [@require_option, rubyopt].compact.reject(&:empty?).join(" ")
          end

          # The saved RUBYOPT with the bootstrap, or nil when Bundler saved none. Bundler
          # 2.5 and later also save and restore an empty RUBYOPT.
          def bundler_original_rubyopt(saved)
            return nil if saved.nil?
            return @require_option if saved == BUNDLER_UNSET

            with_bootstrap(saved)
          end

          def prefix_for(serial)
            serial.nil? ? UNOWNED : "c#{serial}"
          end

          def record_names
            directory = @mutex.synchronize { @directory }
            return [] if directory.nil?

            Dir.children(directory).select { |name| name.end_with?(RECORD_SUFFIX) }
          rescue SystemCallError => e
            Datadog.logger.debug { "Line coverage could not read the records of child processes: #{e.class}: #{e.message}" }
            []
          end

          def read_records(names, keep)
            names.filter_map do |name|
              path = File.join(directory, name)
              data = File.binread(path)
              File.delete(path) unless keep
              self.class.decode_record(data)
            rescue SystemCallError, ArgumentError, TypeError => e
              Datadog.logger.debug { "Line coverage ignored the record of a child process: #{e.class}: #{e.message}" }
              nil
            end
          end
        end

        # Hooks on the methods that start processes, prepended once. They add the child's
        # environment entries and otherwise pass every argument, block and result through.
        #
        # @internal
        module ChildProcessHooks
          def self.install
            return if @installed

            @installed = true
            ::Kernel.prepend(KernelMethods)
            ::Kernel.singleton_class.prepend(KernelMethods)
            ::Process.singleton_class.prepend(ProcessMethods)
            ::IO.singleton_class.prepend(IOMethods)
          end

          # Kernel#spawn, #system, #exec and #`, and the same methods of the Kernel module.
          module KernelMethods
            ruby2_keywords def spawn(*arguments, &block)
              super(*ChildProcesses.spawn_arguments(arguments), &block)
            end

            ruby2_keywords def system(*arguments, &block)
              super(*ChildProcesses.spawn_arguments(arguments), &block)
            end

            ruby2_keywords def exec(*arguments, &block)
              super(*ChildProcesses.spawn_arguments(arguments), &block)
            end

            # Kernel#` takes no environment, so a covered command runs through IO.popen,
            # which reads the same output with the same encoding and sets the same $?.
            def `(command)
              return super unless command.is_a?(String)

              environment = ChildProcesses.command_environment
              return super if environment.nil?

              ::IO.popen(environment, command, &:read)
            end
          end

          # Process.spawn, .exec and ._fork, which Kernel#fork, Process.fork and
          # IO.popen("-") call.
          module ProcessMethods
            ruby2_keywords def spawn(*arguments, &block)
              super(*ChildProcesses.spawn_arguments(arguments), &block)
            end

            ruby2_keywords def exec(*arguments, &block)
              super(*ChildProcesses.spawn_arguments(arguments), &block)
            end

            def _fork
              ChildProcesses.before_fork
              pid = super
              ChildProcesses.after_fork_in_child if pid.zero?
              pid
            end
          end

          # IO.popen. IO.popen("-") forks, which Process._fork covers.
          module IOMethods
            ruby2_keywords def popen(*arguments, &block)
              command = arguments.first.is_a?(Hash) ? arguments[1] : arguments.first
              return super if command == "-"

              super(*ChildProcesses.spawn_arguments(arguments), &block)
            end
          end
        end
      end
    end
  end
end
