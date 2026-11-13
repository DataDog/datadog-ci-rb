# frozen_string_literal: true

require "csv"
require "yaml"
require "pathname"
require "tmpdir"
require "open3"

RSpec.describe Datadog::CI::Contrib::FileAccess::Integration do
  include_context "CI mode activated"

  # Native collectors retain repository boundaries per thread.
  around { |example| Thread.new { example.run }.value }

  let(:itr_enabled) { true }
  let(:code_coverage_enabled) { true }
  let(:root) { Datadog::CI::Git::LocalRepository.root }
  let(:directory) { Dir.mktmpdir("file-access-", root) }
  let(:path) { File.join(directory, "fixture.json") }
  let(:events) { [] }
  let(:component) { Datadog.send(:components).test_impact_analysis }
  let(:patcher) { Datadog::CI::Contrib::FileAccess::Patcher }

  before do
    File.write(path, '{"value":42}')
    allow(component).to receive(:write) { |event| events << event }
  end

  after { FileUtils.remove_entry(directory) }

  def start_session
    test_tracing.start_test_session
    test_tracing.start_test_suite("suite")
  end

  def read_in_test(&block)
    test_tracing.trace_test("reads fixture", "suite", &block)
  end

  def collected_files
    events.last.inspect_coverage.keys.select { |file| file.start_with?(directory + "/") }
  end

  it "does not patch File when the library is required or manually instrumented before configuration" do
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-rdatadog/ci", "-e", <<~RUBY)
      original = File.method(:read).owner
      Datadog.configure { |c| c.ci.enabled = true }
      Datadog::CI::Contrib::Instrumentation.instrument(:fileaccess)
      abort "File was patched" unless File.method(:read).owner == original && original == IO.singleton_class
    RUBY
    expect(status.success?).to be(true), output
  end

  it "installs only after remote configuration enables coverage, and only once" do
    expect(patcher).to receive(:patch).twice.and_wrap_original do |method|
      expect(component).to be_code_coverage
      method.call
    end
    start_session
    Datadog::CI::Contrib::Instrumentation.instrument(:fileaccess)
    expect(File.ancestors.count(Datadog::CI::Contrib::FileAccess::Instrumentation::InstanceMethods)).to eq(1)
  end

  it "enables file coverage when debug logging returns nil" do
    allow(Datadog.logger).to receive(:debug).and_return(nil)
    expect(patcher).to receive(:patch).and_call_original
    start_session
    read_in_test { File.read(path) }

    expect(collected_files).to eq([path])
  end

  it "does not install file hooks when the native extension cannot load" do
    allow(component).to receive(:require)
      .with("datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}").and_raise(LoadError, "extension unavailable")
    expect(patcher).not_to receive(:patch)
    expect(Datadog.logger).to receive(:error).with(/extension unavailable/)
    start_session

    expect(component).not_to be_code_coverage
    read_in_test { expect(File.read(path)).to eq('{"value":42}') }
    expect(events).to be_empty
  end

  it "records a binary-encoded file path inside a Unicode checkout" do
    checkout = File.join(directory, "caf\u00e9")
    FileUtils.mkdir_p(checkout)
    fixture = File.join(checkout, "fixture.json")
    File.write(fixture, '{"value":42}')
    allow(Datadog::CI::Git::LocalRepository).to receive(:root).and_return(checkout)
    start_session

    read_in_test do
      expect(File.read(fixture.b)).to eq('{"value":42}')
    end
    expect(collected_files).to include(fixture)
  end

  context "when coverage is disabled" do
    let(:code_coverage_enabled) { false }

    it "does not invoke the patcher or record reads, even if hooks remain from an earlier session" do
      expect(patcher).not_to receive(:patch)
      expect(component).not_to receive(:record_file_dependency)
      start_session
      read_in_test { File.read(path) }
    end
  end

  context "when TIA is disabled" do
    let(:itr_enabled) { false }

    it "does not invoke the patcher" do
      expect(patcher).not_to receive(:patch)
      start_session
    end
  end

  context "when the integration is disabled" do
    before { Datadog.configuration.ci[:fileaccess].enabled = false }
    after { Datadog.configuration.ci[:fileaccess].enabled = true }

    it "does not invoke the patcher" do
      expect(patcher).not_to receive(:patch)
      start_session
    end
  end

  context "during a coverage-enabled session" do
    before { start_session }

    {
      "File.open" => ->(file) { File.open(file).tap(&:close) },
      "File.new" => ->(file) { File.new(file).tap(&:close) },
      "File.read" => ->(file) { File.read(file) },
      "File.binread" => ->(file) { File.binread(file) },
      "Pathname#read" => ->(file) { Pathname.new(file).read },
      "Pathname#binread" => ->(file) { Pathname.new(file).binread },
      "CSV.read" => ->(file) { CSV.read(file, quote_char: "'") },
      "CSV.foreach" => ->(file) { CSV.foreach(file, quote_char: "'").to_a },
      "YAML.load_file" => ->(file) { YAML.load_file(file) },
      "JSON.parse" => ->(file) { JSON.parse(File.read(file)) }
    }.each do |name, operation|
      it "records #{name} through existing coverage events" do
        read_in_test { operation.call(path) }
        payload = MessagePack.unpack(MessagePack.pack(events.last))
        expect(payload.fetch("files")).to include({"filename" => path.delete_prefix(root + "/")})
      end
    end

    it "records local-file Kernel.open with a literal path" do
      read_in_test do
        Dir.chdir(directory) do
          expect(Kernel.open("fixture.json", &:read)).to eq('{"value":42}')
        end
      end
      expect(collected_files).to eq([path])
    end

    [:read, :binread, :open].each do |method|
      it "records both the symlink and its target through File.#{method}" do
        link = File.join(directory, "alias.json")
        File.symlink("fixture.json", link)

        read_in_test do
          result = File.public_send(method, link)
          result.close if result.is_a?(File)
        end

        payload = MessagePack.unpack(MessagePack.pack(events.last))
        expect(payload.fetch("files")).to include(
          {"filename" => link.delete_prefix(root + "/")},
          {"filename" => path.delete_prefix(root + "/")}
        )
      end
    end

    it "resolves directory symlinks before parent path components" do
      target_directory = File.join(directory, "nested")
      FileUtils.mkdir_p(File.join(target_directory, "child"))
      target = File.join(target_directory, "fixture.json")
      File.write(target, "target contents")
      File.symlink("nested/child", File.join(directory, "alias"))

      read_in_test do
        expect(File.read(File.join(directory, "alias", "..", "fixture.json"))).to eq("target contents")
      end
      expect(collected_files).to contain_exactly(path, target)
    end

    it "records the selected hard-link name when resolving a symlink" do
      hardlink = File.join(directory, "hardlink.json")
      link = File.join(directory, "alias.json")
      File.link(path, hardlink)
      File.symlink("hardlink.json", link)

      read_in_test do
        File.read(link)
      end
      expect(collected_files).to contain_exactly(link, hardlink)
    end

    it "preserves Unicode paths, including targets of ASCII symlinks" do
      unicode = File.join(directory, "caf\u00e9.json")
      link = File.join(directory, "unicode.json")
      File.write(unicode, "Unicode fixture")
      File.symlink(unicode, link)

      read_in_test do
        expect(File.read(unicode)).to eq("Unicode fixture")
        File.read(link)
      end
      expect(collected_files).to match_array([unicode, File.realpath(unicode), link].uniq)
    end

    it "preserves literal tildes and normalizes redundant separators" do
      literal = File.join(directory, "~fixture.json")
      File.write(literal, "literal tilde")

      read_in_test do
        Dir.chdir(directory) do
          expect(File.read("~fixture.json")).to eq("literal tilde")
          File.read("././fixture.json")
          File.read("#{directory}//fixture.json")
        end
      end
      expect(collected_files).to contain_exactly(literal, path)
    end

    it "retains Ruby resolution when the native resolver declines a path" do
      allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies).to receive(:native_paths).and_return(nil)
      link = File.join(directory, "fallback.json")
      File.symlink("fixture.json", link)

      read_in_test do
        Dir.chdir(directory) { File.read("./fallback.json") }
      end
      expect(collected_files).to contain_exactly(link, path)
    end

    it "resolves a symlink again after it is retargeted" do
      link = File.join(directory, "alias.json")
      target = File.join(directory, "other.json")
      File.write(target, "other contents")
      File.symlink(path, link)
      read_in_test { File.read(link) }
      File.unlink(link)
      File.symlink(target, link)
      read_in_test { File.read(link) }

      expect(events.first.inspect_coverage).to include(link => true, path => true)
      expect(events.last.inspect_coverage).to include(link => true, target => true)
      expect(events.last.inspect_coverage).not_to have_key(path)
    end

    it "filters repository boundaries independently for aliases and targets" do
      Dir.mktmpdir("file-access-external-") do |external|
        target = File.join(external, "target.json")
        File.write(target, "external contents")
        internal_link = File.join(directory, "external.json")
        external_link = File.join(external, "internal.json")
        File.symlink(target, internal_link)
        File.symlink(path, external_link)

        read_in_test do
          expect(File.read(internal_link)).to eq("external contents")
          File.read(external_link)
        end
        expect(collected_files).to contain_exactly(internal_link, path)
      end
    end

    it "preserves a dangling symlink dependency and the original IO error" do
      link = File.join(directory, "missing.json")
      File.symlink("missing-target.json", link)

      read_in_test do
        expect { File.read(link) }.to raise_error(Errno::ENOENT)
      end
      expect(collected_files).to eq([link])
    end

    it "does no path normalization or filesystem inspection outside an active test" do
      expect(component).not_to receive(:record_file_dependency)
      expect(File).not_to receive(:absolute_path)
      expect(File).not_to receive(:realpath)
      expect(File).not_to receive(:stat)
      expect(File.read(path)).to eq('{"value":42}')
    end

    it "does not initialize Datadog components from hooks left after a reset" do
      Datadog.send(:reset!)
      expect(File.read(path)).to eq('{"value":42}')
      expect(Datadog.send(:components, allow_initialization: false)).to be_nil
    end

    it "preserves reads when the instrumentation cannot access components" do
      allow(Datadog).to receive(:components).and_call_original
      allow(Datadog).to receive(:components).with(allow_initialization: false).and_raise("components unavailable")
      expect(Kernel).to receive(:warn).with(/components unavailable/)
      expect(File.read(path)).to eq('{"value":42}')
    ensure
      # Shared teardown needs component access while shutting down the tracer.
      allow(Datadog).to receive(:components).with(allow_initialization: false).and_call_original
    end

    it "preserves block return values and records the open" do
      read_in_test do
        result = File.open(path) do |file|
          expect(file.read).to eq('{"value":42}')
          :block_result
        end
        expect(result).to eq(:block_result)
      end
      expect(collected_files).to eq([path])
    end

    it "preserves read arguments and coerces path-like objects only once" do
      pathname = double("path")
      expect(pathname).to receive(:to_path).once.and_return(path)
      read_in_test do
        expect(File.read(pathname, 5, 2, encoding: "UTF-8")).to eq("value")
      end
    end

    it "forwards open keywords and blocks, and binread positional arguments" do
      read_in_test do
        expect(File.open(path, mode: "r", encoding: "UTF-8", &:read)).to eq('{"value":42}')
        expect(File.binread(path, 5, 2)).to eq("value")
      end
    end

    it "preserves customer file and block exceptions" do
      read_in_test do
        expect { File.read(File.join(directory, "missing")) }.to raise_error(Errno::ENOENT)
        expect { File.open(path) { raise "customer failure" } }.to raise_error("customer failure")
      end
    end

    it "normalizes paths at read time and deduplicates repeated dependencies" do
      read_in_test do
        Dir.chdir(directory) do
          2.times { File.read("./fixture.json") }
        end
      end
      expect(collected_files).to eq([path])
    end

    it "updates relative dependencies when the working directory changes in a test" do
      other_directory = File.join(directory, "other")
      Dir.mkdir(other_directory)
      other_path = File.join(other_directory, "fixture.json")
      File.write(other_path, "other contents")

      read_in_test do
        Dir.chdir(directory) { File.read("fixture.json") }
        Dir.chdir(other_directory) { File.read("fixture.json") }
      end
      expect(collected_files).to contain_exactly(path, other_path)
    end

    it "updates relative dependencies when the current directory is renamed" do
      original = File.join(directory, "original")
      renamed = File.join(directory, "renamed")
      Dir.mkdir(original)
      File.write(File.join(original, "fixture.json"), "contents")

      read_in_test do
        Dir.chdir(original) do
          File.read("fixture.json")
          File.rename(original, renamed)
          File.read("fixture.json")
        end
      end
      expect(collected_files).to contain_exactly(
        File.join(original, "fixture.json"), File.join(renamed, "fixture.json")
      )
    end

    it "follows a symlink retargeted between reads in the same test" do
      other_path = File.join(directory, "other.json")
      link = File.join(directory, "alias.json")
      File.write(other_path, "other contents")
      File.symlink("fixture.json", link)

      read_in_test do
        Dir.chdir(directory) do
          File.read("alias.json")
          File.unlink(link)
          File.symlink("other.json", link)
          File.read("alias.json")
        end
      end
      expect(collected_files).to contain_exactly(link, path, other_path)
    end

    it "does not leak dependencies into the next test" do
      read_in_test { File.read(path) }
      read_in_test { nil }
      expect(events.first.inspect_coverage).to have_key(path)
      expect(events.last.inspect_coverage).not_to have_key(path)
    end

    it "collects child-thread reads during the active test" do
      read_in_test do
        Thread.new { File.read(path) }.value
      end
      expect(collected_files).to eq([path])
    end

    context "when native coverage uses single-threaded mode" do
      let(:use_single_threaded_coverage) { true }

      it "still collects file reads from other threads" do
        read_in_test { Thread.new { File.read(path) }.value }
        expect(collected_files).to eq([path])
      end
    end

    it "ignores files outside the repository" do
      read_in_test do
        File.read(File::NULL)
      end
      expect(collected_files).to be_empty
    end

    it "logs recording failures without changing file results, even if logging raises" do
      allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies)
        .to receive(:paths_for).and_raise("record failure")
      expect(Datadog.logger).to receive(:warn).with(/record failure/).and_raise("logger failure")
      read_in_test { expect(File.read(path)).to eq('{"value":42}') }
    end

    it "does not recursively record files opened by the error logger, and resumes after logging" do
      read_in_test do
        allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies)
          .to receive(:paths_for).and_raise("record failure")
        expect(Datadog.logger).to receive(:warn).once do
          File.open(path).tap { |file| file.read }.close
          File.read(path)
        end
        expect(File.read(path)).to eq('{"value":42}')

        allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies)
          .to receive(:paths_for).and_call_original
        File.read(path)
      end
      expect(collected_files).to eq([path])
    end

    [:thread, :fiber].each do |execution_context|
      it "keeps recording in another #{execution_context} while an error is being logged" do
        failed_path = File.join(directory, "failed.json")
        File.write(failed_path, "contents")
        allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies)
          .to receive(:paths_for).and_call_original
        allow_any_instance_of(Datadog::CI::TestImpactAnalysis::Coverage::FileDependencies)
          .to receive(:paths_for).with(failed_path).and_raise("record failure")
        run_other_test = -> { read_in_test { File.read(path) } }

        read_in_test do
          expect(Datadog.logger).to receive(:warn).once do
            if execution_context == :thread
              Thread.new(&run_other_test).value
            else
              Fiber.new(&run_other_test).resume
            end
          end
          expect(File.read(failed_path)).to eq("contents")
        end
        expect(events.size).to eq(2)
        expect(events.map(&:inspect_coverage)).to all include(path => true)
      end
    end

    context "with a bundle exclusion" do
      let(:bundle_path) { directory }

      it "ignores bundled files" do
        read_in_test do
          File.read(path)
        end
        expect(collected_files).to be_empty
      end
    end

    context "with symlinks crossing a bundle boundary" do
      let(:bundle_path) { File.join(directory, "vendor") }

      it "filters the alias and target independently" do
        FileUtils.mkdir_p(bundle_path)
        target = File.join(bundle_path, "fixture.json")
        File.write(target, "vendor contents")
        internal_link = File.join(directory, "vendor.json")
        bundled_link = File.join(bundle_path, "project.json")
        File.symlink(target, internal_link)
        File.symlink(path, bundled_link)

        read_in_test do
          expect(File.read(internal_link)).to eq("vendor contents")
          File.read(bundled_link)
        end
        expect(collected_files).to contain_exactly(internal_link, path)
      end
    end

    context "with suite-level skipping" do
      let(:tia_test_skipping_mode) { Datadog::CI::Ext::Test::TIATestSkippingMode::SUITE }

      it "aggregates file dependencies into the suite event" do
        read_in_test { File.read(path) }
        test_tracing.active_test_suite("suite").finish
        expect(events.last.test_id).to be_nil
        expect(events.last.inspect_coverage).to have_key(path)
      end
    end
  end
end
