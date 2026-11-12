# frozen_string_literal: true

require "csv"
require "yaml"
require "pathname"
require "tmpdir"
require "open3"

RSpec.describe Datadog::CI::Contrib::FileAccess::Integration do
  include_context "CI mode activated"

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

  context "during shared session setup" do
    {
      "File.open" => ->(file) { File.open(file).tap(&:close) },
      "File.read" => ->(file) { File.read(file) },
      "File.binread" => ->(file) { File.binread(file) }
    }.each do |name, operation|
      it "records #{name} at session level and leaves later reads scoped to their test" do
        test_tracing.start_test_session
        expect(component).to be_collecting_session_coverage
        operation.call(path)
        test_tracing.start_test_suite("suite")
        expect(component).not_to be_collecting_session_coverage

        local_path = File.join(directory, "test-only.json")
        File.write(local_path, "{}")
        read_in_test { operation.call(local_path) }

        shared = events.find { |event| event.test_id.nil? && event.test_suite_id.nil? }
        individual = events.find { |event| !event.test_id.nil? }
        expect(shared.inspect_coverage).to include(path => true)
        expect(shared.inspect_coverage).not_to have_key(local_path)
        expect(individual.inspect_coverage).to have_key(local_path)
        expect(individual.inspect_coverage).not_to have_key(path)
      end
    end

    it "excludes reads performed while requiring or loading unused application code" do
      loader = File.join(directory, "eager.rb")
      File.write(loader, "File.read(#{path.dump}); File.binread(#{path.dump}); File.open(#{path.dump}, &:read)")
      test_tracing.start_test_session
      require loader
      load loader
      test_tracing.start_test_suite("suite")

      shared = events.find { |event| event.test_id.nil? && event.test_suite_id.nil? }
      expect(shared.inspect_coverage).not_to have_key(path)
      expect(shared.inspect_coverage).not_to have_key(loader)
    ensure
      $LOADED_FEATURES.delete(loader)
    end

    it "ignores reads before the session, after its first context, and after shutdown" do
      expect(component).not_to receive(:record_file_dependency)
      File.read(path)
      test_tracing.start_test_session
      component.on_test_context_started("group")
      File.read(path)
      component.stop_coverage
      component.shutdown!
      File.read(path)
    end
  end

  context "during a coverage-enabled session" do
    before { start_session }

    {
      "File.open" => ->(file) { File.open(file).tap(&:close) },
      "File.new" => ->(file) { File.new(file).tap(&:close) },
      "Kernel.open" => ->(file) { Kernel.open(file, &:read) },
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

    it "preserves block return values and records the open before running the block" do
      read_in_test do |test|
        result = File.open(path) do |file|
          expect(test.lock_custom_impacted_files).to include(path)
          expect(file.read).to eq('{"value":42}')
          :block_result
        end
        expect(result).to eq(:block_result)
      end
    end

    it "preserves read arguments and coerces path-like objects only once" do
      pathname = double("path")
      expect(pathname).to receive(:to_path).once.and_return(path)
      read_in_test do
        expect(File.read(pathname, 5, 2, encoding: "UTF-8")).to eq("value")
      end
    end

    it "preserves customer file and block exceptions" do
      read_in_test do
        expect { File.read(File.join(directory, "missing")) }.to raise_error(Errno::ENOENT)
        expect { File.open(path) { raise "customer failure" } }.to raise_error("customer failure")
      end
    end

    it "normalizes paths at read time and deduplicates repeated dependencies" do
      read_in_test do |test|
        Dir.chdir(directory) do
          2.times { File.read("./fixture.json") }
        end
        expect(test.lock_custom_impacted_files).to eq([path])
      end
    end

    it "does not leak dependencies into the next test" do
      read_in_test { File.read(path) }
      read_in_test { nil }
      test_events = events.reject { |event| event.test_id.nil? }
      expect(test_events.first.inspect_coverage).to have_key(path)
      expect(test_events.last.inspect_coverage).not_to have_key(path)
    end

    it "does not attribute unrelated thread reads to the active test" do
      read_in_test do |test|
        Thread.new { File.read(path) }.join
        expect(test.lock_custom_impacted_files).to be_empty
      end
    end

    it "ignores files outside the repository" do
      read_in_test do |test|
        File.read(File::NULL)
        expect(test.lock_custom_impacted_files).to be_empty
      end
    end

    it "logs recording failures without changing file results, even if logging raises" do
      read_in_test do |test|
        allow(test).to receive(:add_impacted_files).and_raise("record failure")
        expect(Datadog.logger).to receive(:warn).with(/record failure/).and_raise("logger failure")
        expect(File.read(path)).to eq('{"value":42}')
      end
    end

    context "with a bundle exclusion" do
      let(:bundle_path) { directory }

      it "ignores bundled files" do
        read_in_test do |test|
          File.read(path)
          expect(test.lock_custom_impacted_files).to be_empty
        end
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
