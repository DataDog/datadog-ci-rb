# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/line_coverage"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::ChildProcesses do
  let(:line_coverage_class) { Datadog::CI::TestImpactAnalysis::Coverage::LineCoverage }
  let(:line_files) { Datadog::CI::TestImpactAnalysis::Coverage::LineFiles }
  # Every spec starts the collector for the repository root: it never runs again for another root.
  let(:root) { File.realpath(Datadog::CI::Git::LocalRepository.root) }
  let(:ruby) { RbConfig.ruby }
  let(:leaf_lines) { [1, 2, 3, 4] }
  let(:line_coverage) { line_coverage_class.start(root: root, ignored_paths: []) }
  let(:bootstrap_option) { "-r#{described_class::BOOTSTRAP}" }

  before do
    require "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
    skip "per-test line coverage is not supported on this Ruby" unless line_coverage_class.supported?

    line_coverage_class.stop_collector
    line_coverage.collect_child_processes
  end

  after do
    line_coverage_class.stop_collector
  end

  def fixture(name)
    File.join(__dir__, "fixtures", "child_processes", "#{name}.rb")
  end

  def relative(name)
    Datadog::CI::Git::LocalRepository.relative_to_root(fixture(name))
  end

  # Children start without Bundler, so that each one starts quickly and loads nothing of
  # this repository but the bootstrap.
  def unbundled(&block)
    Bundler.with_unbundled_env(&block)
  end

  def coverage_of(test_id, fixture_ids = [])
    count, packed = line_coverage.finish_test(test_id, fixture_ids)
    line_files.new(count, packed).inspect_coverage
  end

  def in_test(test_id = 1)
    line_coverage.start_test(test_id)
    yield
    coverage_of(test_id)
  end

  def child_processes
    described_class.current
  end

  describe "the processes a test starts" do
    it "credits the test with the lines of a child started with Kernel#system" do
      expect(in_test { unbundled { system(ruby, fixture("leaf")) } }).to include(relative("leaf") => leaf_lines)
    end

    it "credits the test with the lines of a child started with Kernel#spawn" do
      coverage = in_test { unbundled { Process.wait(spawn(ruby, fixture("leaf"))) } }

      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    it "credits the test with the lines of a child started with Process.spawn and Kernel.system" do
      coverage = in_test do
        unbundled do
          Process.wait(Process.spawn(ruby, fixture("leaf")))
          Kernel.system(ruby, fixture("other_leaf"))
        end
      end

      expect(coverage).to include(relative("leaf") => leaf_lines, relative("other_leaf") => leaf_lines)
    end

    it "credits the test with the lines of a child started with backticks" do
      expect(in_test { unbundled { `#{ruby} #{fixture("leaf")}` } }).to include(relative("leaf") => leaf_lines)
    end

    it "credits the test with the lines of a child started with IO.popen or Open3" do
      coverage = in_test do
        unbundled do
          IO.popen([ruby, fixture("leaf")], &:read)
          Open3.capture2(ruby, fixture("other_leaf"))
        end
      end

      expect(coverage).to include(relative("leaf") => leaf_lines, relative("other_leaf") => leaf_lines)
    end

    it "credits the test with the lines of a forked child and of a program it executes" do
      coverage = in_test do
        unbundled do
          Process.wait(fork { load fixture("leaf") })
          Process.wait(fork { exec(ruby, fixture("other_leaf")) })
        end
      end

      expect(coverage).to include(relative("leaf") => leaf_lines, relative("other_leaf") => leaf_lines)
    end

    it "credits the test with the lines of a program that a child forked by IO.popen executes" do
      coverage = in_test { unbundled { IO.popen("-") { |io| io ? io.read : exec(ruby, fixture("leaf")) } } }

      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    # Ruby ends that child with _exit after the block, which skips the exit handlers.
    it "leaves out the lines that a child forked by IO.popen with a block runs itself" do
      coverage = in_test { IO.popen("-") { |io| io ? io.read : load(fixture("leaf")) } }

      expect(coverage).not_to have_key(relative("leaf"))
    end

    it "credits the test with the lines of a child's child" do
      coverage = in_test { unbundled { system(ruby, fixture("spawner"), ruby, fixture("leaf")) } }

      expect(coverage).to include(relative("spawner") => [1], relative("leaf") => leaf_lines)
    end

    it "credits the test with the lines of a child that forks" do
      coverage = in_test { unbundled { system(ruby, fixture("forker"), fixture("leaf")) } }

      expect(coverage).to include(relative("forker") => [1, 2], relative("leaf") => leaf_lines)
    end

    it "credits the test with the lines that a child runs in its last exit handler" do
      coverage = in_test { unbundled { system(ruby, "-r", fixture("loads_leaf_at_exit"), "-e", "nil") } }

      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    # The child inherits the handler, which then runs after every handler the child registers.
    it "credits the test with the lines that a forked child runs in an exit handler of its parent" do
      in_forked_child = false
      at_exit { load(fixture("leaf")) if in_forked_child }
      coverage = in_test { Process.wait(fork { in_forked_child = true }) }

      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    # Ruby removes every event hook after the exit handlers, before it ends the other threads.
    it "leaves out the lines that a child runs after its exit handlers" do
      coverage = in_test { unbundled { system(ruby, fixture("exits_thread")) } }

      expect(coverage).to include(relative("exits_thread") => [3, 4, 5, 6, 10])
      expect(coverage).not_to have_key(relative("leaf"))
    end

    # The children keep Bundler: changing the environment from two threads would race.
    it "credits each of two concurrent tests with the lines of its own children" do
      both_started = Queue.new
      tests = {1 => "leaf", 2 => "other_leaf"}.map do |test_id, name|
        Thread.new do
          line_coverage.start_test(test_id)
          both_started << test_id
          sleep 0.01 until both_started.size == 2
          system(ruby, fixture(name))
        end
      end
      tests.each(&:join)

      first = coverage_of(1)
      second = coverage_of(2)
      expect(first).to include(relative("leaf") => leaf_lines)
      expect(first).not_to have_key(relative("other_leaf"))
      expect(second).to include(relative("other_leaf") => leaf_lines)
      expect(second).not_to have_key(relative("leaf"))
    end

    it "leaves out a child that finishes after its test, whose lines are unowned" do
      Dir.mktmpdir do |directory|
        signal = File.join(directory, "go")
        pid = nil
        coverage = in_test { pid = unbundled { spawn(ruby, fixture("waits"), signal) } }
        FileUtils.touch(signal)
        Process.wait(pid)

        expect(coverage).not_to have_key(relative("leaf"))
        unowned = line_coverage.shared.fetch("unowned")
        expect(line_files.lines(unowned.fetch(relative("leaf")))).to eq(leaf_lines)
      end
    end

    it "puts the lines of a child started outside any test in the unowned lines" do
      unbundled { system(ruby, fixture("leaf")) }

      unowned = line_coverage.shared.fetch("unowned")
      expect(line_files.lines(unowned.fetch(relative("leaf")))).to eq(leaf_lines)
    end

    it "credits a child started by a fixture to its tests, then to the suite setup lines" do
      line_coverage.start_fixture("fixture")
      unbundled { system(ruby, fixture("leaf")) }
      line_coverage.start_test(1)
      expect(coverage_of(1, ["fixture"])).to include(relative("leaf") => leaf_lines)
      line_coverage.start_test(2)
      expect(coverage_of(2, ["fixture"])).to include(relative("leaf") => leaf_lines)
      line_coverage.release_fixture("fixture")

      suite_setup = line_coverage.shared.fetch("suiteSetup")
      expect(line_files.lines(suite_setup.fetch(relative("leaf")))).to eq(leaf_lines)
    end
  end

  describe "the environment of a child" do
    it "names the test's records and puts the bootstrap first in the caller's RUBYOPT" do
      output = nil
      in_test { output = unbundled { IO.popen({"RUBYOPT" => "-W0"}, [ruby, fixture("environment")], &:read) } }
      prefix, rubyopt = eval(output) # rubocop:disable Security/Eval

      expect(File.dirname(prefix)).to eq(child_processes.directory)
      expect(File.basename(prefix)).to match(/\Ac\d+\z/)
      expect(rubyopt).to eq("#{bootstrap_option} -W0")
    end

    it "puts the bootstrap first in the inherited RUBYOPT" do
      output = nil
      in_test { output = IO.popen([ruby, fixture("environment")], &:read) }
      _prefix, rubyopt = eval(output) # rubocop:disable Security/Eval

      expect(rubyopt).to eq([bootstrap_option, ENV["RUBYOPT"]].compact.reject(&:empty?).join(" "))
    end

    it "does not cover a child whose environment the caller replaces" do
      output = nil
      coverage = in_test do
        output = IO.popen({"PATH" => ENV["PATH"]}, [ruby, fixture("environment")], unsetenv_others: true, &:read)
        system({"PATH" => ENV["PATH"]}, ruby, fixture("leaf"), unsetenv_others: true)
      end

      expect(eval(output)).to eq([nil, nil]) # rubocop:disable Security/Eval
      expect(coverage).not_to have_key(relative("leaf"))
    end

    it "does not cover a child whose RUBYOPT the caller unsets" do
      coverage = in_test { system({"RUBYOPT" => nil}, ruby, fixture("leaf")) }

      expect(coverage).not_to have_key(relative("leaf"))
    end

    # As Rake does when it starts the test runner, which runs its own session.
    it "is unchanged in a process where no test session collects line coverage" do
      line_coverage_class.stop_collector
      line_coverage_class.start(root: root, ignored_paths: [])

      output = unbundled { IO.popen({"RUBYOPT" => "-W0"}, [ruby, fixture("environment")], &:read) }

      expect(eval(output)).to eq([nil, "-W0"]) # rubocop:disable Security/Eval
      expect(child_processes).to be_nil
    end
  end

  describe "the RUBYOPT that Bundler saved, in the environment of a child" do
    let(:print_saved_rubyopt) { [ruby, "-e", "print ENV['BUNDLER_ORIG_RUBYOPT'].inspect"] }

    def saved_rubyopt_in_child(caller_environment)
      output = nil
      in_test { output = unbundled { IO.popen(caller_environment, print_saved_rubyopt, &:read) } }
      output
    end

    it "gets the bootstrap first" do
      expect(saved_rubyopt_in_child({"BUNDLER_ORIG_RUBYOPT" => "-W0"})).to eq("#{bootstrap_option} -W0".inspect)
    end

    it "gets the bootstrap when Bundler saved that RUBYOPT was not set" do
      saved = saved_rubyopt_in_child({"BUNDLER_ORIG_RUBYOPT" => described_class::BUNDLER_UNSET})

      expect(saved).to eq(bootstrap_option.inspect)
    end

    it "gets the bootstrap when it is empty" do
      expect(saved_rubyopt_in_child({"BUNDLER_ORIG_RUBYOPT" => ""})).to eq(bootstrap_option.inspect)
    end

    it "gets the bootstrap first when the child inherits it" do
      output = nil
      in_test do
        output = unbundled do
          ENV["BUNDLER_ORIG_RUBYOPT"] = "-W0"
          IO.popen(print_saved_rubyopt, &:read)
        end
      end

      expect(output).to eq("#{bootstrap_option} -W0".inspect)
    end

    it "is not added when Bundler saved none" do
      expect(saved_rubyopt_in_child({})).to eq("nil")
    end

    it "stays unset when the caller unsets it" do
      expect(saved_rubyopt_in_child({"BUNDLER_ORIG_RUBYOPT" => nil})).to eq("nil")
    end
  end

  describe "RUBYLIB in the environment of a child" do
    let(:hook) { described_class::RUBYGEMS_HOOK }
    let(:rubylib) { ["/rubylib/a", "/rubylib/b"].join(File::PATH_SEPARATOR) }

    def load_path_in_child(caller_environment)
      output = nil
      in_test { output = unbundled { IO.popen(caller_environment, [ruby, fixture("load_path")], &:read) } }
      eval(output) # rubocop:disable Security/Eval
    end

    it "gets the hook directory first, and the child's load path stays the one it has without it" do
      child_rubylib, load_path = load_path_in_child({"RUBYLIB" => rubylib, "RUBYOPT" => "-W0"})
      uncovered_output = unbundled { IO.popen({"RUBYLIB" => rubylib, "RUBYOPT" => nil}, [ruby, fixture("load_path")], &:read) }
      _, uncovered_load_path = eval(uncovered_output) # rubocop:disable Security/Eval

      expect(child_rubylib).to eq([hook, rubylib].join(File::PATH_SEPARATOR))
      expect(load_path).to eq(uncovered_load_path)
      expect(load_path.first(2)).to eq(["/rubylib/a", "/rubylib/b"])
    end

    it "gets the hook directory first when the child inherits it" do
      output = nil
      in_test do
        output = unbundled do
          ENV["RUBYLIB"] = rubylib
          IO.popen([ruby, fixture("load_path")], &:read)
        end
      end
      child_rubylib, = eval(output) # rubocop:disable Security/Eval

      expect(child_rubylib).to eq([hook, rubylib].join(File::PATH_SEPARATOR))
    end

    it "keeps every entry of a RUBYLIB that holds empty ones, in order, after the hook directory" do
      rubylib_with_empty_entries = ["", "/rubylib/a", "", "/rubylib/b", ""].join(File::PATH_SEPARATOR)
      child_rubylib, load_path = load_path_in_child({"RUBYLIB" => rubylib_with_empty_entries, "RUBYOPT" => "-W0"})
      uncovered_output = unbundled do
        IO.popen({"RUBYLIB" => rubylib_with_empty_entries, "RUBYOPT" => nil}, [ruby, fixture("load_path")], &:read)
      end
      _, uncovered_load_path = eval(uncovered_output) # rubocop:disable Security/Eval

      expect(child_rubylib).to eq([hook, rubylib_with_empty_entries].join(File::PATH_SEPARATOR))
      expect(load_path).to eq(uncovered_load_path)
      expect(load_path.first(2)).to eq(["/rubylib/a", "/rubylib/b"])
    end

    it "gets the hook directory alone when it is empty" do
      child_rubylib, = load_path_in_child({"RUBYLIB" => ""})

      expect(child_rubylib).to eq(hook)
    end

    it "is left as it is when the hook directory's path holds the separator" do
      child_processes_with_unusable_hook = described_class.new(
        root: root,
        ignored_paths: [],
        extension_path: described_class.loaded_extension_path,
        rubygems_hook: File.join(Dir.tmpdir, "rubygems#{File::PATH_SEPARATOR}hook")
      )
      entries = nil
      in_test { entries = child_processes_with_unusable_hook.environment({"RUBYLIB" => rubylib}) }

      expect(entries).not_to have_key("RUBYLIB")
      expect(entries.fetch("RUBYOPT")).to start_with(bootstrap_option)
    ensure
      child_processes_with_unusable_hook&.remove_directory
    end

    it "stays unset when the caller unsets it" do
      child_rubylib, = load_path_in_child({"RUBYLIB" => nil})

      expect(child_rubylib).to be_nil
    end

    it "lets a defaults file of the user's own, which the hook directory hides, load as before" do
      user_rubylib = File.join(__dir__, "fixtures", "child_processes", "user_defaults")
      output = nil
      coverage = in_test do
        output = unbundled { IO.popen({"RUBYLIB" => user_rubylib}, [ruby, fixture("leaf")], &:read) }
      end
      uncovered_output = unbundled { IO.popen({"RUBYLIB" => user_rubylib, "RUBYOPT" => nil}, [ruby, fixture("leaf")], &:read) }

      expect(output).to eq("user defaults loaded;")
      expect(uncovered_output).to eq(output)
      expect(coverage).to include(relative("leaf") => leaf_lines)
    end
  end

  # As in a child of a process that `bundle exec` started, which inherits BUNDLER_SETUP:
  # puma's tests start puma that way. RubyGems loads Bundler while it starts, before
  # what RUBYOPT names, and Bundler.setup evaluates the gemspec, which may run
  # repository code.
  describe "a child that RubyGems starts with Bundler" do
    let(:manifest_lines) { [1, 2, 3] }

    it "credits the test with the repository code that Bundler.setup runs" do
      coverage = in_test do
        unbundled { system({"BUNDLER_SETUP" => fixture("bundler_setup")}, ruby, fixture("leaf")) }
      end

      expect(coverage).to include(relative("manifest") => manifest_lines, relative("leaf") => leaf_lines)
    end

    it "loses the lines of methods that code runs when the caller unsets RUBYLIB" do
      coverage = in_test do
        unbundled { system({"BUNDLER_SETUP" => fixture("bundler_setup"), "RUBYLIB" => nil}, ruby, fixture("leaf")) }
      end

      expect(coverage.fetch(relative("manifest"), [])).not_to include(2)
      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    context "through `bundle exec` with a gemspec that runs repository code" do
      around do |example|
        Dir.mktmpdir("datadog-ci-child-processes-bundle-") do |directory|
          gemfile = File.join(directory, "Gemfile")
          # Bundler 4 exports BUNDLE_LOCKFILE for `bundle exec`, so without it a nested
          # `bundle exec` writes this bundle's lock over the test bundle's.
          @bundle_environment = {"BUNDLE_GEMFILE" => gemfile, "BUNDLE_LOCKFILE" => "#{gemfile}.lock"}
          File.write(gemfile, "gemspec\n")
          File.write(File.join(directory, "child_processes_fixture.gemspec"), <<~GEMSPEC)
            require #{fixture("manifest").inspect}
            child_processes_manifest
            Gem::Specification.new do |spec|
              spec.name = "child_processes_fixture"
              spec.version = "0.0.1"
              spec.summary = "Runs repository code when Bundler evaluates it"
              spec.authors = ["Datadog"]
            end
          GEMSPEC
          example.run
        end
      end

      it "credits the test with that code in a program started without Bundler" do
        coverage = in_test do
          unbundled { system(@bundle_environment, "bundle", "exec", ruby, fixture("leaf")) }
        end

        expect(coverage).to include(relative("manifest") => manifest_lines, relative("leaf") => leaf_lines)
      end

      it "credits the test with that code in a program started from the test's own bundle" do
        coverage = in_test { system(@bundle_environment, "bundle", "exec", ruby, fixture("leaf")) }

        expect(coverage).to include(relative("manifest") => manifest_lines, relative("leaf") => leaf_lines)
      end

      it "loses the lines of methods that code runs when the caller unsets RUBYLIB" do
        coverage = in_test do
          unbundled { system(@bundle_environment.merge("RUBYLIB" => nil), "bundle", "exec", ruby, fixture("leaf")) }
        end

        expect(coverage.fetch(relative("manifest"), [])).not_to include(2)
        expect(coverage).to include(relative("leaf") => leaf_lines)
      end
    end
  end

  # As puma does when it restarts or prunes the bundle.
  describe "a program that a child runs with Bundler's original environment" do
    def run_with_original_environment(*program)
      stdout, stderr, status = unbundled do
        Open3.capture3({"BUNDLER_ORIG_RUBYOPT" => "-W0"}, ruby, fixture("unbundled_exec"), *program)
      end
      [stdout, stderr, status.success?]
    end

    it "is covered, but the lines that the child runs before it executes the program are lost" do
      coverage = in_test do
        unbundled do
          system(
            {"BUNDLER_ORIG_RUBYOPT" => described_class::BUNDLER_UNSET},
            ruby, fixture("unbundled_exec"), ruby, fixture("leaf")
          )
        end
      end

      expect(coverage).to include(relative("leaf") => leaf_lines)
      # A process that executes another program never runs its exit handlers.
      expect(coverage).not_to have_key(relative("unbundled_exec"))
    end

    it "runs uncovered and unchanged in another Ruby" do
      result = nil
      coverage = in_test do
        File.write(File.join(child_processes.directory, "config"), "ruby 0.0.0 0 0 other\n/nonexistent.so\n#{root}")
        result = run_with_original_environment(ruby, "-e", "print ENV['RUBYOPT']")
        run_with_original_environment(ruby, fixture("leaf"))
      end

      expect(result).to eq(["#{bootstrap_option} -W0", "", true])
      expect(coverage).not_to have_key(relative("leaf"))
    end

    it "runs uncovered and unchanged when the collector does not load" do
      result = nil
      coverage = in_test do
        File.write(
          File.join(child_processes.directory, "config"),
          [described_class.identity, "/nonexistent/datadog_ci_native.so", root].join("\n")
        )
        result = run_with_original_environment(ruby, "-e", "print ENV['RUBYOPT']")
        run_with_original_environment(ruby, fixture("leaf"))
      end

      expect(result).to eq(["#{bootstrap_option} -W0", "", true])
      expect(coverage).not_to have_key(relative("leaf"))
    end
  end

  describe "the hooked methods" do
    it "pass options and keywords through and return what the original methods return" do
      Dir.mktmpdir do |directory|
        in_test do
          unbundled do
            expect(system(ruby, "-e", "exit 0")).to be(true)
            expect(system(ruby, "-e", "exit 3")).to be(false)
            expect(system("/nonexistent/datadog-ci-command")).to be_nil
            expect { system(ruby, "-e", "exit 3", exception: true) }.to raise_error(RuntimeError, /exit 3/)

            reader, writer = IO.pipe
            pid = spawn(ruby, "-e", "print Dir.pwd", chdir: directory, out: writer)
            writer.close
            expect(pid).to be_a(Integer)
            Process.wait(pid)
            expect(reader.read).to eq(File.realpath(directory))
          end
        end
      end
    end

    it "start the child unchanged when the hook fails" do
      allow(child_processes).to receive(:environment).and_raise(RuntimeError, "hook failure")

      coverage = in_test { expect(unbundled { system(ruby, fixture("leaf")) }).to be(true) }

      expect(coverage).not_to have_key(relative("leaf"))
    end
  end

  describe "the child bootstrap" do
    def run_child(*arguments)
      unbundled { Open3.capture3(ruby, *arguments) }
    end

    it "leaves a child of another Ruby uncovered and unchanged" do
      coverage = in_test do
        File.write(File.join(child_processes.directory, "config"), "ruby 0.0.0 0 0 other\n/nonexistent.so\n#{root}")
        stdout, stderr, status = run_child("-e", "print :done")
        expect([stdout, stderr, status.success?]).to eq(["done", "", true])
        run_child(fixture("leaf"))
      end

      expect(coverage).not_to have_key(relative("leaf"))
    end

    it "leaves a child uncovered and unchanged when the collector does not load" do
      coverage = in_test do
        File.write(
          File.join(child_processes.directory, "config"),
          [described_class.identity, "/nonexistent/datadog_ci_native.so", root].join("\n")
        )
        stdout, stderr, status = run_child("-e", "print :done")
        expect([stdout, stderr, status.success?]).to eq(["done", "", true])
        run_child(fixture("leaf"))
      end

      expect(coverage).not_to have_key(relative("leaf"))
    end

    it "leaves a child unchanged, and its test covered, when the transport directory is gone" do
      coverage = in_test do
        directory = child_processes.directory
        FileUtils.rm_rf(directory)
        stdout, stderr, status = run_child("-e", "print :done")

        expect([stdout, stderr, status.success?]).to eq(["done", "", true])
        expect(File.exist?(directory)).to be(false)
      end

      expect(coverage).to have_key(Datadog::CI::Git::LocalRepository.relative_to_root(__FILE__))
    end

    it "covers a child that closes its standard output" do
      coverage = in_test do
        _stdout, stderr, status = run_child(fixture("closes_stdout"))
        expect([stderr, status.success?]).to eq(["", true])
      end

      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    it "lets the test finish without the lines of a child that is killed" do
      coverage = in_test do
        pid = unbundled { spawn(ruby, "-e", "sleep 30") }
        Process.kill("KILL", pid)
        _pid, status = Process.wait2(pid)
        expect(status.termsig).to eq(9)
      end

      expect(coverage.keys).to all(satisfy { |file| !file.include?("fixtures/child_processes/") })
    end

    # The bootstrap removes the Datadog constants that loading the native extension created,
    # so datadog-ci, loaded later, finds the extension loaded but not its classes.
    it "covers a child that loads datadog-ci by code, whose own test session runs without coverage" do
      rspec = Gem.bin_path("rspec-core", "rspec")
      output = nil
      status = nil
      coverage = in_test do
        output = IO.popen([ruby, rspec, fixture("nested_session")], err: [:child, :out], &:read)
        status = $?
      end

      expect(status).to be_success, output
      expect(output).to include("1 example, 0 failures")
      expect(coverage).to have_key(relative("nested_session"))
    end

    it "keeps those constants for datadog-ci when auto instrumentation in RUBYOPT loads it later" do
      output = nil
      coverage = in_test do
        output = IO.popen(
          {"RUBYOPT" => "-rbundler/setup -rdatadog/ci/auto_instrument"},
          [ruby, fixture("loads_datadog_ci")], err: [:child, :out], &:read
        )
      end

      expect(output).to eq("[true, true, 1]")
      expect(coverage).to have_key(relative("loads_datadog_ci"))
    end

    it "keeps them, and loads the extension once, in a program that a child runs with Bundler's original environment" do
      output = nil
      coverage = in_test do
        output = IO.popen(
          {"BUNDLER_ORIG_RUBYOPT" => "-rbundler/setup -r datadog/ci/auto_instrument"},
          [ruby, fixture("original_exec"), ruby, fixture("loads_datadog_ci")], err: [:child, :out], &:read
        )
      end

      expect(output).to eq("[true, true, 1]")
      expect(coverage).to have_key(relative("loads_datadog_ci"))
    end

    it "loads nothing but the RubyGems hook and the native extension, by their paths, before the libraries that RUBYOPT names" do
      environment = {"RUBYOPT" => "-r#{fixture("loaded_features")}"}
      covered = nil
      in_test { covered = unbundled { IO.popen(environment, [ruby, "-e", "0"], &:read) } }
      line_coverage_class.stop_collector
      uncovered = unbundled { IO.popen(environment, [ruby, "-e", "0"], &:read) }

      loaded = eval(covered) - eval(uncovered) # rubocop:disable Security/Eval
      expect(loaded).to contain_exactly(
        File.join(described_class::RUBYGEMS_HOOK, "rubygems", "defaults", "ruby.rb"),
        described_class::BOOTSTRAP,
        described_class.loaded_extension_path
      )
    end

    it "leaves the source code features unavailable, not broken, in a child that loads them by code" do
      output = nil
      in_test { output = unbundled { IO.popen([ruby, "-I", File.join(root, "lib"), fixture("source_code")], &:read) } }

      expect(output).to eq("[nil, []]")
    end

    it "leaves the Datadog constant to the child" do
      stdout = nil
      coverage = in_test do
        stdout, _stderr, _status = run_child(fixture("defines_datadog"), chdir: Dir.tmpdir)
      end

      expect(stdout).to eq("nil Class")
      expect(coverage.fetch(relative("defines_datadog"))).to include(1, 2, 4)
    end
  end

  describe "backticks" do
    def original_backtick(command)
      ::Kernel.instance_method(:`).super_method.bind_call(self, command)
    end

    # The hooked backtick covers the command only while the collector runs, as here.
    def hooked_backtick(command)
      `#{command}`
    end

    # The status of the previous command is known, so an error that leaves $? unchanged
    # shows as that status.
    def outcome
      original_backtick("exit 7")
      output = yield
      [output, output.encoding, $?.exitstatus, $?.termsig, $?.success?]
    rescue SystemCallError => e
      [e.class, e.message, $?.exitstatus]
    end

    def expect_same_outcome(command)
      original = outcome { original_backtick(command) }
      hooked = outcome { hooked_backtick(command) }

      expect(hooked).to eq(original)
      hooked
    end

    it "returns the same output, encoding and exit status" do
      expect(expect_same_outcome("printf 'caf\\303\\251'; exit 3")).to eq(["café".b.force_encoding(Encoding.default_external), Encoding.default_external, 3, nil, false])
    end

    it "sets $? to the status of the same child" do
      [:original_backtick, :hooked_backtick].each do |backtick|
        pid = Integer(send(backtick, "echo $$"))
        expect($?.pid).to eq(pid)
      end
    end

    it "reports the same signal for a command that a signal kills" do
      expect(expect_same_outcome("kill -9 $$")).to eq(["", Encoding.default_external, nil, 9, nil])
    end

    it "lets the command's standard error through" do
      [:original_backtick, :hooked_backtick].each do |backtick|
        reader, writer = IO.pipe
        saved = $stderr.dup
        begin
          $stderr.reopen(writer)
          send(backtick, "echo to-stderr 1>&2")
        ensure
          $stderr.reopen(saved)
          writer.close
        end
        expect(reader.read).to eq("to-stderr\n")
      end
    end

    it "raises the same errors for a missing or a non-executable command" do
      expect(expect_same_outcome("/nonexistent/datadog-ci-command").first).to eq(Errno::ENOENT)

      Dir.mktmpdir do |directory|
        command = File.join(directory, "not-executable")
        File.write(command, "echo not run\n")
        expect(expect_same_outcome(command).first).to eq(Errno::EACCES)
      end
    end

    it "runs a command through a shell exactly when the original does" do
      direct = "#{ruby} #{fixture("parent_pid")}"
      shell = "#{direct}; true"

      [direct, shell].each do |command|
        original = Integer(original_backtick(command)) == Process.pid
        hooked = unbundled { Integer(hooked_backtick(command)) == Process.pid }
        expect(hooked).to eq(original)
      end
      expect(Integer(original_backtick(direct))).to eq(Process.pid)
      expect(Integer(original_backtick(shell))).not_to eq(Process.pid)
    end

    it "returns the same very large output" do
      command = "#{ruby} -e 'STDOUT.write(%q(x) * 8_000_000)'"

      expect(unbundled { expect_same_outcome(command) }.first.bytesize).to eq(8_000_000)
    end

    it "returns the same output in another thread" do
      expect(Thread.new { expect_same_outcome("echo threaded") }.value.first).to eq("threaded\n")
    end

    # What Object#stub of minitest-mock does, as this bundle has no minitest.
    def stub_like_minitest(object, name, value)
      stub_name = "__minitest_stub__#{name}"
      metaclass = object.singleton_class
      metaclass.send(:alias_method, stub_name, name)
      metaclass.send(:define_method, name) { |*| value }
      yield
    ensure
      metaclass.send(:undef_method, name)
      metaclass.send(:alias_method, name, stub_name)
      metaclass.send(:undef_method, stub_name)
    end

    it "leaves a backtick stubbed with rspec-mocks stubbed" do
      object = Object.new
      allow(object).to receive(:`).and_return("stubbed")

      expect(object.send(:`, "echo real")).to eq("stubbed")
    end

    it "leaves a backtick stubbed with minitest stubbed, and covers the command once the stub is gone" do
      object = Object.new
      stub_like_minitest(object, :`, "stubbed") do
        expect(object.send(:`, "echo real")).to eq("stubbed")
      end

      coverage = in_test do
        expect(object.send(:`, "echo real")).to eq("real\n")
        unbundled { object.send(:`, "#{ruby} #{fixture("leaf")}") }
      end
      expect(coverage).to include(relative("leaf") => leaf_lines)
    end

    # Without the hooks, the backtick's own frame is the only one above its caller.
    it "adds two frames from the hooks to the backtrace of an error" do
      locations = begin
        original_backtick("/nonexistent/datadog-ci-command")
      rescue Errno::ENOENT => e
        e.backtrace_locations
      end
      expect(locations.first(3).map(&:base_label)).to eq(["`", "bind_call", "original_backtick"])

      locations = begin
        hooked_backtick("/nonexistent/datadog-ci-command")
      rescue Errno::ENOENT => e
        e.backtrace_locations
      end
      expect(locations.first(4).map(&:base_label)).to eq(["popen", "popen", "`", "hooked_backtick"])
      expect(locations.first(3).map(&:path).uniq).to eq([File.join(File.dirname(described_class::BOOTSTRAP), "child_processes.rb")])
    end
  end
end
