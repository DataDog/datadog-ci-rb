# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../../../lib/datadog/ci/test_impact_analysis/coverage/session"

RSpec.describe Datadog::CI::TestImpactAnalysis::Coverage::Session do
  let(:root) { File.realpath(Dir.mktmpdir("session-coverage")) }
  let(:collector) { described_class.new(root: root, ignored_path: File.join(root, "vendor")) }

  def write_source(path, source)
    filename = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, source)
    filename
  end

  def define_method_from(path, method_name)
    filename = write_source(path, "def self.#{method_name}; true; end")
    fixture.module_eval(File.read(filename), filename)
    filename
  end

  let(:fixture) { Module.new }

  after do
    collector.stop
    Thread.current[:session_coverage] = nil
    $LOADED_FEATURES.reject! { |path| path.start_with?(root + "/") }
    FileUtils.remove_entry(root)
  end

  it "keeps the shared helper but excludes eagerly required unused application and support files" do
    unused = write_source("app/unused.rb", "Class.new { def work; true; end }")
    support = write_source("spec/support/unused.rb", "Class.new { def work; true; end }")
    helper = write_source("spec/spec_helper.rb", "require_relative '../app/unused'\nrequire_relative 'support/unused'")
    require helper

    collector.start
    expect(collector.stop).to eq(helper => true)
    expect($LOADED_FEATURES).to include(unused, support)
  end

  it "records methods and blocks executed during shared setup" do
    setup = define_method_from("support/setup.rb", :setup)
    block_file = write_source("support/hook.rb", "proc { true }")
    hook = fixture.module_eval(File.read(block_file), block_file)

    collector.start
    fixture.setup
    hook.call
    expect(collector.stop).to eq(setup => true, block_file => true)
  end

  it "ignores nested requires and load bodies, then records subsequent use" do
    used = define_method_from("app/used.rb", :used)
    unused = write_source("app/eager.rb", "Class.new { def work; true; end }")
    loader = write_source("boot.rb", "require_relative 'app/eager'\nload #{unused.dump}")

    collector.start
    require loader
    fixture.used
    expect(collector.stop).to eq(used => true)
  end

  it "collects shared fixture reads but excludes IO performed by eager-loading bodies" do
    fixture_path = write_source("fixtures/shared.json", "{}")
    unused_path = write_source("fixtures/unused.json", "{}")
    loader = write_source("boot.rb", "Thread.current[:session_coverage].record_file_read(#{unused_path.dump})")

    collector.start
    Thread.current[:session_coverage] = collector
    require loader
    collector.record_file_read(fixture_path)
    expect(collector.stop).to eq(fixture_path => true)
  end

  it "resumes after a failing require" do
    used = define_method_from("app/used.rb", :used)
    collector.start
    begin
      require File.join(root, "missing.rb")
    rescue LoadError
      fixture.used
    end
    expect(collector.stop).to eq(used => true)
  end

  it "excludes bundled files and paths outside the repository boundary" do
    define_method_from("vendor/gem/setup.rb", :vendor_setup)
    source = "def self.outside; true; end"
    fixture.module_eval(source, root + "-other/setup.rb")
    collector.start
    fixture.vendor_setup
    fixture.outside
    expect(collector.stop).to be_empty
  end

  it "collects setup from background threads" do
    setup = define_method_from("support/thread_setup.rb", :setup)
    collector.start
    Thread.new { fixture.setup }.join
    expect(collector.stop).to eq(setup => true)
  end

  it "does not suppress setup in one thread while another thread loads a file" do
    setup = define_method_from("support/thread_setup.rb", :setup)
    loader = write_source("boot.rb", "Thread.current[:ready] << true\nThread.current[:release].pop")
    ready = Queue.new
    release = Queue.new
    collector.start
    worker = Thread.new do
      Thread.current[:ready] = ready
      Thread.current[:release] = release
      require loader
    end
    ready.pop
    fixture.setup
    release << true
    worker.join
    expect(collector.stop).to eq(setup => true)
  end

  it "stops cleanly, is idempotent, and does not retain dependencies across runs" do
    setup = define_method_from("support/setup.rb", :setup)
    collector.start
    collector.start
    fixture.setup
    expect(collector.stop).to eq(setup => true)
    fixture.setup
    expect(collector.stop).to be_empty
    collector.start
    expect(collector.stop).to be_empty
  end

  it "preserves inherited setup in a fork while keeping child-only dependencies out of the parent" do
    skip "fork is unavailable" unless Process.respond_to?(:fork)
    parent = define_method_from("support/parent.rb", :parent_setup)
    child = define_method_from("support/child.rb", :child_setup)
    child_fixture = write_source("fixtures/child.json", "{}")
    reader, writer = IO.pipe
    collector.start
    fixture.parent_setup
    pid = fork do
      reader.close
      fixture.child_setup
      collector.record_file_read(child_fixture)
      Marshal.dump(collector.stop, writer)
      writer.close
      exit! 0
    end
    writer.close
    child_coverage = Marshal.load(reader)
    reader.close
    Process.wait(pid)
    expect(child_coverage).to eq(parent => true, child => true, child_fixture => true)
    expect(collector.stop).to eq(parent => true)
  end

  it "logs collection failures without raising into the setup callback" do
    define_method_from("support/setup.rb", :setup)
    unread = write_source("fixtures/unused.json", "{}")
    allow(collector).to receive(:record).and_raise("collection failed")
    expect(Datadog.logger).to receive(:warn).with(/Failed to collect session coverage/)
    collector.start
    expect { fixture.setup }.not_to raise_error
    collector.record_file_read(unread)
    expect(collector.stop).to be_empty
  end
end
